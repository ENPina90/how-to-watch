require 'net/http'
require 'json'

class TmdbService
  BASE_URL = 'https://api.themoviedb.org/3'

  def fetch_imdb_id(tmdb_id, type = 'movie')
    url = case type
          when 'movie'
            "#{BASE_URL}/movie/#{tmdb_id}?api_key=#{ENV['TMDB_API_KEY']}"
          when 'show'
            "#{BASE_URL}/tv/#{tmdb_id}/external_ids?api_key=#{ENV['TMDB_API_KEY']}"
          else
            raise "Invalid type. Must be 'movie' or 'tv'."
          end

    response = Net::HTTP.get(URI(url))
    parsed_response = JSON.parse(response)
    parsed_response['imdb_id']
  rescue StandardError => e
    puts "Error fetching IMDb ID: #{e.message}"
    nil
  end

  def fetch_trailer_url(entry)
    return nil unless entry.tmdb

    url = URI("#{BASE_URL}/movie/#{entry.tmdb}/videos?api_key=#{ENV['TMDB_API_KEY']}")

    begin
      # Make the HTTP request
      response = Net::HTTP.get(url)
      parsed_response = JSON.parse(response)

      # Find the first YouTube trailer
      trailer = parsed_response['results'].find { |video| video['type'] == 'Trailer' && video['site'] == 'YouTube' }

      if trailer && trailer['key']
        # Return the YouTube link
        "https://www.youtube.com/watch?v=#{trailer['key']}"
      else
        puts "No trailer found for Entry ##{entry.id}"
        nil
      end

    rescue StandardError => e
      puts "Error fetching trailer for Entry ##{entry.id}: #{e.message}"
      nil
    end
  end
end
