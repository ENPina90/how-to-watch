class OmdbApi
  URL = "http://www.omdbapi.com/?"
  API_KEYS = [ENV['API_KEY_1'], ENV['API_KEY_2'], ENV['API_KEY_3']]

  def self.search_by_title(title, number: 1, year: nil)
    query = "#{URL}s=#{CGI.escape(title.strip)}&apikey=#{API_KEYS.sample}"
    data = api_call(query)
    return nil if data["Error"]

    select_movies(data, number, year)
  end

  def self.get_movie(imdb_id)
    query = "#{URL}i=#{imdb_id}&apikey=#{API_KEYS.sample}"
    response = api_call(query)
    response if response&.dig("Type") == "movie" || "series" || "episode" && response["Poster"] != "N/A"
  end

  def self.api_call(query)
    response = URI.parse(query).open.read
    JSON.parse(response)
  rescue OpenURI::HTTPError => error
    Rails.logger.error("Failed OMDB API call: #{error}")
    nil
  end

  def self.select_movies(response, number, year)
    movies = year.nil? ? response["Search"].first(number) : response["Search"].select do |m|
      (year.to_i - 1..year.to_i + 1).include?(m["Year"].to_i)
    end
    movies.map { |movie| movie["imdbID"] }
  end
end
