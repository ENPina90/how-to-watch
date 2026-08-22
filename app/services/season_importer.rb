# frozen_string_literal: true

# Imports a whole season: one parent `series`/`anime` entry plus a Subentry per episode.
#
# Extracted from ListsController#add_season. This is the slowest thing the app does — one
# TMDB call for the season, one per episode for its imdb id, and for anime one more per
# preceding season — so it is the prime candidate for moving into a job (plan item #14).
# Keeping it as a plain object means that move is a one-line change at the call site.
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
          imdb: episode_imdb_id(number),
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

  # Episodes carry their own imdb ids, but the lookup is optional -- a missing one just
  # means the subentry inherits the series id.
  def episode_imdb_id(number)
    @tmdb.fetch_episode_external_ids(@tmdb_id, @season, number)['imdb_id'].presence || @series_imdb_id
  rescue TmdbService::RequestError => e
    Rails.logger.warn "Could not fetch IMDB id for episode #{number}: #{e.message}"
    @series_imdb_id
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
  # restarting at 1.
  def absolute_episode_offset
    return 0 if @season <= 1

    (1...@season).sum do |previous_season|
      @tmdb.fetch_season(@tmdb_id, previous_season)['episodes']&.length.to_i
    rescue TmdbService::RequestError => e
      Rails.logger.warn "Could not fetch season #{previous_season}: #{e.message}"
      0
    end
  end

  def anime?
    @media_type == 'anime'
  end

  def result(status, entry, message, added = 0, failed = [])
    { status: status, entry: entry, message: message, episodes_added: added, episodes_failed: failed }
  end
end
