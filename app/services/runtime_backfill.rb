# frozen_string_literal: true

# Fills in the runtimes the catalogue is missing, from TMDB.
#
# A programme with no runtime is kept off the cable schedule (CableSchedule::MIN_MINUTES),
# so every blank one is a film or an episode missing from the dial. Most of them are blank
# because OMDB had no figure when the entry was imported, and TMDB very often does -- it is
# where the season importers already take an episode's runtime from. So the weekly sweep
# asks it first, and only what it cannot answer becomes a notification.
#
# Why TMDB and not the provider. VidSrc's data API ("Whether a title will actually play" in
# VIDSRC.md) answers with a title, a file name and a backdrop, and no duration -- checked
# 2026-09-19. The only place VidSrc says how long a file is is the player's own
# PLAYER_EVENT, inside a browser. That is picked up separately -- see
# EntriesController#runtime -- and fills whatever this cannot.
#
# Fills a gap and never overwrites, the same rule EntriesController#runtime keeps: a runtime
# somebody typed in is a considered value, not TMDB's to correct. "A gap" is anything under
# MIN_MINUTES, since that is what the schedule treats as missing.
#
# What it deliberately does not look up:
#   - fanedits and custom entries. A fanedit's runtime is the editor's, not the film's, and
#     TMDB's figure for the source film would be confidently wrong.
#   - a standalone episode with no series imdb. Its imdb id is often not the episode's own:
#     Oats Studios' shorts all carry the id of the volume they came out in, and a lookup by
#     it answers with the volume's runtime for every one of them.
class RuntimeBackfill
  Result = Struct.new(:checked, :filled, :unanswered, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(tmdb: TmdbService.new)
    @tmdb = tmdb
    @checked = 0
    @filled = 0
  end

  def call
    fill_episodes
    fill_entries

    Result.new(checked: @checked, filled: @filled, unanswered: @checked - @filled)
  end

  private

  def bare = Arel.sql("COALESCE(length, 0) < #{CableSchedule::MIN_MINUTES}")

  # Series episodes, a season at a time: one request answers every episode in it, and a
  # show missing runtimes is usually missing a whole season's worth.
  def fill_episodes
    Subentry.where(bare).where.not(season: nil).where.not(episode: nil)
            .includes(:entry).group_by(&:entry).each do |show, episodes|
      show_id = show_tmdb_id(show.series_imdb.presence || show.imdb, known: show.tmdb)

      episodes.group_by(&:season).each do |season, in_season|
        @checked += in_season.size
        next unless show_id

        runtimes = season_runtimes(show_id, season)
        in_season.each { |episode| fill(episode, runtimes[episode.episode.to_i]) }
      end
    end
  end

  # Films and standalone episodes. Series are left out: a show's own length is not read by
  # the schedule -- its episodes' are, above.
  def fill_entries
    Entry.where(bare).where(media: %w[movie episode]).where.not(imdb: [nil, '']).find_each do |entry|
      @checked += 1
      fill(entry, entry.media == 'movie' ? movie_runtime(entry) : episode_runtime(entry))
    end
  end

  def fill(record, minutes)
    return if minutes.to_i < CableSchedule::MIN_MINUTES

    # update_column, as EntriesController#runtime does: this is a figure arriving from
    # outside, not an edit, and it should not bump updated_at or run the entry's callbacks.
    record.update_column(:length, minutes.to_i)
    @filled += 1
    Rails.logger.info("Runtime filled from TMDB for #{record.class.name.downcase} #{record.id}: #{minutes} min")
  end

  # The show's TMDB id. The one on the entry is trusted when it is there, since that is what
  # the importers wrote; otherwise it is looked up by imdb id.
  def show_tmdb_id(imdb, known: nil)
    return known if known.present?
    return if imdb.blank?

    ask { @tmdb.find_by_imdb_id(imdb)['tv_results']&.first&.dig('id') }
  end

  def season_runtimes(show_id, season)
    payload = ask { @tmdb.fetch_season(show_id, season) } || {}

    Array(payload['episodes']).to_h { |episode| [episode['episode_number'].to_i, episode['runtime']] }
  end

  # By the imdb id rather than the entry's `tmdb`, because the imdb id is what the provider
  # plays -- a runtime for some other record TMDB happens to be keyed to would be no use.
  def movie_runtime(entry)
    movie_id = ask { @tmdb.find_by_imdb_id(entry.imdb)['movie_results']&.first&.dig('id') }
    return unless movie_id

    ask { @tmdb.fetch_movie(movie_id)['runtime'] }
  end

  def episode_runtime(entry)
    return if entry.series_imdb.blank? || entry.season.blank? || entry.episode.blank?

    show_id = show_tmdb_id(entry.series_imdb)
    return unless show_id

    ask { @tmdb.fetch_episode(show_id, entry.season, entry.episode)['runtime'] }
  end

  # One title TMDB cannot answer for -- not found, or a blip -- is one title left for the
  # notification. It is not a reason to stop the sweep.
  def ask
    yield
  rescue TmdbService::RequestError => e
    Rails.logger.warn("Runtime backfill: #{e.message}")
    nil
  end
end
