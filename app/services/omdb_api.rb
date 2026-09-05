# frozen_string_literal: true

require 'open-uri'

class OmdbApi

  URL = 'http://www.omdbapi.com/?'
  API_KEYS = [
    ENV['OMDB_API_KEY_1'],
    ENV['OMDB_API_KEY_2'],
    ENV['OMDB_API_KEY_3']
  ].freeze

  def self.search_by_title(title, number: 1, year: nil)
    query = "#{URL}s=#{CGI.escape(title.strip)}&apikey=#{API_KEYS.sample}"
    data = api_call(query)
    return nil if data['Error']

    select_movies(data, number, year)
  end

  # The search endpoint's own payload already carries a Poster for every match, so the
  # poster picker can offer several candidate titles without a follow-up lookup per result.
  # Separate from search_by_title, which returns ids for the importer and assumes a
  # well-formed payload.
  def self.search_with_posters(title, year: nil, limit: 3)
    return [] if title.blank?

    query = "#{URL}s=#{CGI.escape(title.strip)}&apikey=#{API_KEYS.sample}"
    query += "&y=#{year.to_i}" if year.to_i.positive?
    data = api_call(query)
    return [] if data.nil? || data['Error'].present? || data['Search'].blank?

    data['Search'].first(limit).filter_map do |result|
      poster = result['Poster']
      next if poster.blank? || poster == 'N/A'

      { poster: poster, title: result['Title'], year: result['Year'] }
    end
  end

  def self.get_movie(imdb_id)
    query = "#{URL}i=#{imdb_id}&apikey=#{API_KEYS.sample}"
    response = api_call(query)
    return if response.nil?
    return unless ['movie', 'series', 'episode'].include?(response['Type']) && response['Poster'] != 'N/A'

    # if response['Type'] == 'series'
    #   get_series_episodes(response)
    # end
    response
  end

  def self.api_call(query)
    response = URI.parse(query).open.read
    JSON.parse(response)
  rescue OpenURI::HTTPError => e
    Rails.logger.error("Failed OMDB API call for query: #{query}, error: #{e}")
    nil
  end

  def self.select_movies(data, number, year)
    movies = if year == nil
      data['Search'].first(number)
    else
      data['Search'].select do |movie|
        (year.to_i - 1..year.to_i + 1).include?(movie['Year'].to_i)
      end
    end
    movies.map { |movie| movie['imdbID'] }
  end

  def self.get_series_episodes(main_entry)
    # `season` holds the season *count* for series entries. OMDB omits totalSeasons for
    # some titles, and `nil.times` used to blow up here and surface as a bogus
    # "already exists" flash.
    if main_entry.season.to_i < 1
      Rails.logger.warn "Entry #{main_entry.id} (#{main_entry.name}) has no season count; skipping episode import"
      return
    end

    # If we have a TMDB ID, use TMDB for better episode data (including plots)
    if main_entry.tmdb.present?
      fetch_episodes_from_tmdb(main_entry)
    else
      # Fallback to OMDB (no plot data available)
      main_entry.season.times do |season|
        query = "#{URL}i=#{main_entry.imdb}&Season=#{season + 1}&apikey=#{API_KEYS.sample}"
        response = api_call(query)
        next unless response

        response['Episodes'].each do |episode|
          Subentry.create_from_source(main_entry, episode, season + 1)
        end
      end
    end

    # Find first episode (season and episode are stored as strings)
    first_episode = Subentry.find_by(entry: main_entry, season: 1, episode: 1)
    first_episode ||= main_entry.subentries.order(:season, :episode).first

    main_entry.update(current: first_episode) if first_episode
  end

  def self.fetch_episodes_from_tmdb(main_entry)
    require 'open-uri'
    tmdb_api_key = TmdbService.api_key
    series_imdb = main_entry.imdb

    main_entry.season.times do |season_index|
      season_number = season_index + 1
      season_url = "https://api.themoviedb.org/3/tv/#{main_entry.tmdb}/season/#{season_number}?api_key=#{tmdb_api_key}"

      begin
        season_data = JSON.parse(URI.open(season_url).read)

        season_data['episodes'].each do |episode_data|
          Subentry.create!(
            entry: main_entry,
            season: season_number,
            episode: episode_data['episode_number'],
            name: episode_data['name'],
            plot: episode_data['overview'], # TMDB provides overview/plot
            imdb: series_imdb,
            rating: episode_data['vote_average'].to_f,
            completed: false
          )
        end
      rescue => e
        Rails.logger.error "Failed to fetch TMDB season #{season_number} for entry #{main_entry.id}: #{e.message}"
      end
    end
  end

  def self.normalize_omdb_data(result)
    normalized_data = {
      media:    result['Type'],
      name:     result['Title'],
      imdb:     result['imdbID'],
      tmdb:     result['tmdb'],
      year:     result['Year'].to_i,
      pic:      result['Poster'],
      genre:    result['Genre'],
      director: result['Director'],
      writer:   result['Writer'],
      actors:   result['Actors'],
      plot:     result['Plot'],
      length:   result['Runtime'].split(' ')[0].to_i,
      rating:   result['imdbRating'].to_f,
      language: result['Language'],
      episode:  result['Episode']&.to_i,
      season:   result['Season']&.to_i || result['totalSeasons']&.to_i,
    }

    if result['seriesID']
      normalized_data[:series_imdb] = result['seriesID']
      series_data = get_movie(result['seriesID'])
      normalized_data[:series] = series_data['Title'] if series_data
    end

    normalized_data
  end

end
