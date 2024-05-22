# frozen_string_literal: true

class OmdbApi

  URL = 'http://www.omdbapi.com/?'
  API_KEYS = [
    ENV['API_KEY_1'],
    ENV['API_KEY_2'],
    ENV['API_KEY_3']
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
    return unless response

    if ['movie', 'series', 'episode'].include?(response['Type']) && response['Poster'] != 'N/A'
      response
    end
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

  def self.normalize_omdb_data(result)
    normalized_data = {
      media:    result['Type'],
      name:     result['Title'],
      imdb:     result['imdbID'],
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
      season:   result['Season']&.to_i,
    }

    if result['seriesID']
      normalized_data[:imdb] = result['seriesID']
      series_data = get_movie(result['seriesID'])
      normalized_data[:category] = series_data['Title'] if series_data
    end

    normalized_data
  end

end
