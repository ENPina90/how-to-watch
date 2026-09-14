# frozen_string_literal: true

# Adds the episodes a show has aired since one `series` entry was filled in.
#
# "New" means after the last episode the entry already holds -- the show has carried on
# past where the entry ends. Gaps further back are a failed import, not news, and an entry
# holding nothing at all is an import that never happened; neither is this class's business,
# and both would otherwise arrive as a flood of "new episode" notifications for a show that
# finished years ago.
#
# The two shapes of `series` entry are extended differently:
#   - a whole show (from `OmdbApi.get_series_episodes`) takes new episodes of its latest
#     season and any seasons after it;
#   - a single season (from `SeasonImporter`, named "<Show> - Season N") only ever takes
#     more of season N. The next season is a new entry by that convention, not more of this
#     one.
#
# The hard part is telling a released episode from a placeholder. TMDB lists a season as
# soon as it is announced, with real titles and overviews for episodes that are weeks away
# (The Simpsons had season 38 up, titled, a fortnight before its premiere), and OMDB's
# `totalSeasons` counts seasons nobody has made yet. So an episode is taken only when all of
# these hold:
#   - it is at or before the show's `last_episode_to_air`, which is TMDB's own statement of
#     how far the show has got;
#   - its `air_date` is strictly before today. The date is the premiere in the show's home
#     timezone, and providers lag a broadcast by hours, so "tonight" is not yet playable;
#   - it looks finished: a title that is not "Episode 5", and a runtime. TMDB fills these in
#     over the days after broadcast, and a runtime is what cable lays a slot out by. Inside
#     GRACE_PERIOD an unfinished one is held back for next week; after it, what is there is
#     all there is going to be, and it is taken as it stands.
#
# Network first, then one transaction for the writes, so no request is ever made with a
# transaction held open. The block, if given, runs inside that transaction for each
# subentry created -- which is how NewEpisodeNotifier makes an episode and its
# notifications land together. Without that, a crash between the two would leave an
# episode nobody was told about, and the next run would not see it as new.
class NewEpisodeImporter
  Result = Struct.new(:added, :held_back, :skipped, keyword_init: true)

  GRACE_PERIOD = 14.days

  # TMDB's stand-in title for an episode it knows nothing about yet, and the other
  # stand-ins that turn up in its data.
  PLACEHOLDER_NAME = /\A(?:episode|ep\.?)\s*#?\s*\d+(?:\.\d+)?\z|\At\.?b\.?[ad]\.?\z/i

  def initialize(entry:, tmdb: TmdbService.new, today: Date.current)
    @entry = entry
    @tmdb = tmdb
    @today = today
  end

  def call(&on_added)
    last_held = @entry.subentries.order(season: :desc, episode: :desc).pick(:season, :episode)
    return skipped('it has no episodes to carry on from') if last_held.nil?

    tmdb_id = resolve_tmdb_id
    return skipped('no TMDB show matches it') if tmdb_id.blank?
    return skipped('its TMDB id cannot be confirmed as this show') unless confirmed_show?(tmdb_id)

    show = @tmdb.fetch_show(tmdb_id)
    last_aired = aired_marker(show)
    return skipped('TMDB has no aired episodes for it') if last_aired.nil?

    ready, held_back = released_episodes(tmdb_id, show, last_held, last_aired)
    added = create_subentries(ready, &on_added)

    Result.new(added: added, held_back: held_back, skipped: nil)
  end

  private

  # A season entry keeps to its own season; a whole show runs from its latest to the last
  # one aired. Seasons TMDB does not list are left out rather than asked for and 404'd.
  def seasons_to_check(show, last_held, last_aired)
    range = season_entry? ? [@entry.season.to_i] : (last_held.first..last_aired.first).to_a
    listed = Array(show['seasons']).map { |season| season['season_number'].to_i }

    # Season 0 is specials, which have no place in the running order.
    range.select { |number| number.positive? && number <= last_aired.first && listed.include?(number) }
  end

  # Walks forward from the last held episode and stops at the first that is not ready.
  # Stopping, rather than skipping past it, matters: an episode held back this week has to
  # still be "after the last held episode" next week, and it would not be if a later one had
  # been added over its head.
  def released_episodes(tmdb_id, show, last_held, last_aired)
    ready = []

    seasons_to_check(show, last_held, last_aired).each do |number|
      episodes = Array(@tmdb.fetch_season(tmdb_id, number)['episodes'])
                 .sort_by { |episode| episode['episode_number'].to_i }

      episodes.each do |episode|
        marker = [number, episode['episode_number'].to_i]
        next if (marker <=> last_held) <= 0
        return [ready, 0] if (marker <=> last_aired).positive?

        case readiness(episode)
        when :ready then ready << episode.merge('season_number' => number)
        when :held_back then return [ready, 1]
        else return [ready, 0]
        end
      end
    end

    [ready, 0]
  end

  def readiness(episode)
    aired = parse_date(episode['air_date'])
    return :unreleased if aired.nil? || aired >= @today
    return :ready if finished?(episode) || aired <= @today - GRACE_PERIOD

    :held_back
  end

  def finished?(episode)
    name = episode['name'].to_s.strip

    name.present? && !name.match?(PLACEHOLDER_NAME) && episode['runtime'].to_i.positive?
  end

  def create_subentries(episodes)
    return [] if episodes.empty?

    ActiveRecord::Base.transaction do
      episodes.map do |episode|
        subentry = @entry.subentries.create!(
          season: episode['season_number'],
          episode: episode['episode_number'],
          name: episode['name'],
          plot: episode['overview'],
          # As in SeasonImporter: playback keys off the entry's imdb id, never the
          # subentry's, so the show's id is all this needs.
          imdb: @entry.imdb,
          rating: episode['vote_average'],
          length: episode['runtime'],
          completed: false
        )
        yield subentry, episode if block_given?
        subentry
      end
    end
  end

  # `last_episode_to_air` as a [season, episode] pair, or nil. A special (season 0) in that
  # slot says nothing about how far the numbered seasons have got, so it counts as nothing.
  def aired_marker(show)
    last = show['last_episode_to_air']
    return nil if last.nil? || last['season_number'].to_i < 1

    [last['season_number'].to_i, last['episode_number'].to_i]
  end

  def season_entry?
    @entry.season.present? && @entry.name.to_s.end_with?(" - Season #{@entry.season}")
  end

  # Nearly every series carries its TMDB id. The odd one that does not is looked up by imdb
  # id rather than skipped -- that lookup is the same show by construction.
  def resolve_tmdb_id
    return @entry.tmdb if @entry.tmdb.present?
    return nil if @entry.imdb.blank?

    @resolved_by_imdb = true
    Array(@tmdb.find_by_imdb_id(@entry.imdb)['tv_results']).first&.dig('id')&.to_s
  end

  # Entries have picked up the wrong TMDB id before (see IMPROVEMENT_PLAN #31) -- one had
  # a 2005 documentary pointing at a Dutch variety show from 1960, which would have gained
  # fifty-one episodes. Filing another show's episodes into this one, and telling everybody
  # about them, is much worse than adding nothing, so the id has to be shown to belong to
  # this show, not merely not shown to belong to another.
  #
  # TMDB's own imdb id settles it when there is one. Plenty of older shows have none -- that
  # Dutch one did not -- and for those, looking the entry's imdb id up has to lead back to
  # the same TMDB id. An entry with no imdb id has nothing to check against and is taken on
  # trust.
  def confirmed_show?(tmdb_id)
    return true if @resolved_by_imdb || @entry.imdb.blank?

    tmdb_imdb = @tmdb.fetch_show_external_ids(tmdb_id)['imdb_id']
    return tmdb_imdb == @entry.imdb if tmdb_imdb.present?

    Array(@tmdb.find_by_imdb_id(@entry.imdb)['tv_results']).any? { |show| show['id'].to_s == tmdb_id.to_s }
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def skipped(reason)
    Result.new(added: [], held_back: 0, skipped: reason)
  end
end
