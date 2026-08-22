# frozen_string_literal: true

# Creates a standalone `episode` entry from TMDB data.
#
# Extracted from EntriesController#handle_episode_from_tmdb, which mixed the TMDB calls,
# the duplicate check and the entry creation in with turbo-stream rendering. Keeping it
# here makes it testable and reusable from a job (see plan item #14).
#
# Returns { status:, entry:, message: } where status is one of:
#   :created   — the entry was inserted
#   :duplicate — the list already has this episode (entry is the existing row)
#   :failed    — TMDB was unreachable or the entry could not be saved
class EpisodeImporter
  def initialize(list:, tmdb_id:, season:, episode:, imdb_id: nil, tmdb: TmdbService.new)
    @list = list
    @tmdb_id = tmdb_id
    @season = season.to_i
    @episode = episode.to_i
    @imdb_id = imdb_id.presence
    @tmdb = tmdb
  end

  def call
    show = @tmdb.fetch_show(@tmdb_id)
    episode_data = @tmdb.fetch_episode(@tmdb_id, @season, @episode)
    series_imdb_id = resolve_series_imdb_id

    existing = find_existing(series_imdb_id)
    return result(:duplicate, existing, 'Episode already added') if existing

    # The source columns are legacy but still the playback fallback, so they are written
    # for parity until plan item #20 retires them.
    series_imdb_id ||= "tmdb#{@tmdb_id}"

    entry = Entry.create!(
      list: @list,
      position: Entry.next_position(@list),
      name: "#{show['name']} - #{episode_data['name']}",
      series: show['name'],
      media: 'episode',
      imdb: series_imdb_id,
      tmdb: @tmdb_id,
      season: @season,
      episode: @episode,
      plot: episode_data['overview'],
      pic: TmdbService.image_url(episode_data['still_path']),
      source: "https://vidsrc.cc/v3/embed/tv/#{series_imdb_id}/#{@season}/#{@episode}",
      source_two: "https://v2.vidsrc.me/embed/#{series_imdb_id}/#{@season}-#{@episode}",
      rating: episode_data['vote_average'],
      year: episode_data['air_date']&.split('-')&.first&.to_i,
      length: episode_data['runtime'] || 0,
      completed: false
    )

    result(:created, entry, "#{entry.name} added to #{@list.name}")
  rescue TmdbService::RequestError, ActiveRecord::RecordInvalid => e
    Rails.logger.error "EpisodeImporter failed for tmdb=#{@tmdb_id} S#{@season}E#{@episode}: #{e.message}"
    result(:failed, nil, "Failed to add episode: #{e.message}")
  end

  # The identifier the list page uses to address this episode's add/remove button.
  def dom_key
    "S#{@season}E#{@episode}"
  end

  private

  def resolve_series_imdb_id
    return @imdb_id if @imdb_id

    @tmdb.fetch_show_external_ids(@tmdb_id)['imdb_id'].presence
  rescue TmdbService::RequestError => e
    # Not fatal: we fall back to a tmdb-derived id below.
    Rails.logger.warn "Could not fetch IMDB id for tmdb=#{@tmdb_id}: #{e.message}"
    nil
  end

  def find_existing(series_imdb_id)
    scope = { season: @season, episode: @episode, media: 'episode' }

    if series_imdb_id.present?
      @list.entries.find_by(scope.merge(imdb: series_imdb_id))
    else
      @list.entries.find_by(scope.merge(tmdb: @tmdb_id))
    end
  end

  def result(status, entry, message)
    { status: status, entry: entry, message: message }
  end
end
