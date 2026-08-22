# frozen_string_literal: true

# Imports a whole season: one parent `series`/`anime` entry plus a Subentry per episode.
#
# Extracted from ListsController#add_season. It used to make one TMDB call per episode
# (for an imdb id nothing reads) plus one per preceding season for anime — around 26
# sequential round trips for a normal season. It now makes one, or two for anime past
# season 1, which is why this no longer needs to be a background job.
#
# Returns { status:, entry:, message:, episodes_added:, episodes_failed: } where status is:
#   :created   — the season entry and its episodes were inserted
#   :duplicate — this list already has that season
#   :failed    — TMDB was unreachable or the parent entry could not be saved
class SeasonImporter
  def initialize(list:, tmdb_id:, series_imdb_id:, series_name:, season:, media_type: 'series', tmdb: TmdbService.new)
    @list = list
    @tmdb_id = tmdb_id
    @series_imdb_id = series_imdb_id
    @series_name = series_name
    @season = season.to_i
    @media_type = media_type.presence || 'series'
    @tmdb = tmdb
  end

  def call
    season_data = @tmdb.fetch_season(@tmdb_id, @season)

    existing = @list.entries.find_by(name: entry_name, series: @series_name)
    return result(:duplicate, existing, "#{entry_name} already exists in this list") if existing

    entry = create_season_entry(season_data)
    added, failed = create_subentries(entry, season_data['episodes'] || [])

    first_episode = entry.subentries.order(:episode).first
    entry.update(current: first_episode) if first_episode

    message = "#{entry_name} added with #{added} episodes"
    message += " (#{failed.length} episodes failed)" if failed.any?

    result(:created, entry, message, added, failed)
  rescue TmdbService::RequestError, ActiveRecord::RecordInvalid => e
    Rails.logger.error "SeasonImporter failed for tmdb=#{@tmdb_id} season=#{@season}: #{e.message}"
    result(:failed, nil, "Failed to add season: #{e.message}")
  end

  private

  def entry_name
    @entry_name ||= "#{@series_name} - Season #{@season}"
  end

  def create_season_entry(season_data)
    Entry.create!(
      list: @list,
      name: entry_name,
      series: @series_name,
      media: @media_type,
      imdb: @series_imdb_id,
      tmdb: @tmdb_id,
      position: Entry.next_position(@list),
      season: @season,
      source: anime? ? "https://vidsrc.cc/v2/embed/anime/#{@series_imdb_id}" : "https://vidsrc.cc/v3/embed/tv/#{@series_imdb_id}",
      source_two: "https://v2.vidsrc.me/embed/#{@series_imdb_id}",
      pic: TmdbService.image_url(season_data['poster_path']),
      plot: season_data['overview'],
      year: season_data['air_date']&.split('-')&.first&.to_i
    )
  end

  def create_subentries(entry, episodes)
    offset = anime? ? absolute_episode_offset : 0
    added = 0
    failed = []

    episodes.each do |episode_data|
      number = episode_data['episode_number']

      begin
        Subentry.create!(
          entry: entry,
          season: @season,
          episode: number,
          name: episode_data['name'],
          plot: episode_data['overview'],
          # Playback keys off the entry's imdb id (see Source#entry_variables); a
          # subentry's own id is never read, so it is not worth a request per episode.
          imdb: @series_imdb_id,
          source: subentry_source(number, offset),
          rating: episode_data['vote_average'],
          completed: false
        )
        added += 1
      rescue StandardError => e
        Rails.logger.error "Failed to create subentry for episode #{number}: #{e.message}"
        failed << number
      end
    end

    [added, failed]
  end

  def subentry_source(number, offset)
    if anime?
      # Anime is numbered continuously across seasons, and the provider wants /sub.
      "https://vidsrc.cc/v2/embed/anime/#{@series_imdb_id}/#{offset + number}/sub"
    else
      "https://vidsrc.cc/v3/embed/tv/#{@series_imdb_id}/#{@season}/#{number}"
    end
  end

  # How many episodes precede this season, so anime numbering continues rather than
  # restarting at 1. The show payload already carries every season's episode_count, so
  # this is one request rather than one per preceding season.
  def absolute_episode_offset
    return 0 if @season <= 1

    seasons = @tmdb.fetch_show(@tmdb_id)['seasons'] || []
    seasons.sum do |season|
      number = season['season_number'].to_i
      # season 0 is Specials, which absolute numbering skips
      number.positive? && number < @season ? season['episode_count'].to_i : 0
    end
  rescue TmdbService::RequestError => e
    Rails.logger.warn "Could not fetch show #{@tmdb_id} for anime numbering: #{e.message}"
    0
  end

  def anime?
    @media_type == 'anime'
  end

  def result(status, entry, message, added = 0, failed = [])
    { status: status, entry: entry, message: message, episodes_added: added, episodes_failed: failed }
  end
end
