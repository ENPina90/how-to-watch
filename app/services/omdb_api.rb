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
    first_episode = Subentry.find_by(entry: main_entry, season: '1', episode: '1')
    first_episode ||= main_entry.subentries.order(Arel.sql('CAST(NULLIF(season, \'\') AS INTEGER), CAST(NULLIF(episode, \'\') AS INTEGER)')).first

    if first_episode
      main_entry.update(current: first_episode)
      # Fix the source URL if needed
      first_episode.fix_source_url! if first_episode.source.blank? || first_episode.source.include?('//-')
    end
  end

  def self.fetch_episodes_from_tmdb(main_entry)
    require 'open-uri'
    tmdb_api_key = ENV['TMDB_API_KEY'] || '7e1c210d0c877abff8a40398735ce605'
    series_imdb = main_entry.imdb

    main_entry.season.times do |season_index|
      season_number = season_index + 1
      season_url = "https://api.themoviedb.org/3/tv/#{main_entry.tmdb}/season/#{season_number}?api_key=#{tmdb_api_key}"

      begin
        season_data = JSON.parse(URI.open(season_url).read)

        season_data['episodes'].each do |episode_data|
          # Calculate absolute episode for anime
          absolute_episode = if main_entry.media == 'anime'
            # Count all previous episodes
            main_entry.subentries.count + 1
          else
            episode_data['episode_number']
          end

          # Generate source URL
          source_url = if main_entry.media == 'anime'
            "https://vidsrc.cc/v2/embed/anime/#{series_imdb}/#{absolute_episode}/sub"
          else
            "https://vidsrc.cc/v3/embed/tv/#{series_imdb}/#{season_number}/#{episode_data['episode_number']}"
          end

          Subentry.create!(
            entry: main_entry,
            season: season_number.to_s,
            episode: episode_data['episode_number'].to_s,
            name: episode_data['name'],
            plot: episode_data['overview'], # TMDB provides overview/plot
            imdb: series_imdb,
            source: source_url,
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
