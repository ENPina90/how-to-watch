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

  def fetch_poster_url(tmdb_id, media_type = 'movie')
    return nil unless tmdb_id

    url = case media_type
          when 'movie'
            "#{BASE_URL}/movie/#{tmdb_id}?api_key=#{ENV['TMDB_API_KEY']}"
          when 'tv', 'show', 'episode'
            "#{BASE_URL}/tv/#{tmdb_id}?api_key=#{ENV['TMDB_API_KEY']}"
          else
            "#{BASE_URL}/movie/#{tmdb_id}?api_key=#{ENV['TMDB_API_KEY']}"
          end

    begin
      response = Net::HTTP.get(URI(url))
      parsed_response = JSON.parse(response)
      poster_path = parsed_response['poster_path']

      if poster_path
        # TMDB images base URL with w500 size (good quality, not too large)
        "https://image.tmdb.org/t/p/w500#{poster_path}"
      else
        puts "No poster found for TMDB ID: #{tmdb_id}"
        nil
      end

    rescue StandardError => e
      puts "Error fetching poster for TMDB ID #{tmdb_id}: #{e.message}"
      nil
    end
  end

  def fetch_omdb_poster_url(imdb_id)
    return nil unless imdb_id

    begin
      # Use the existing OmdbApi service to get movie data
      omdb_data = OmdbApi.get_movie(imdb_id)

      if omdb_data && omdb_data['Poster'] && omdb_data['Poster'] != 'N/A'
        poster_url = omdb_data['Poster']

        # Validate the OMDB poster URL before returning it
        if validate_image_url(poster_url)
          poster_url
        else
          puts "OMDB poster URL is not accessible for IMDB ID: #{imdb_id}"
          nil
        end
      else
        puts "No poster found in OMDB for IMDB ID: #{imdb_id}"
        nil
      end

    rescue StandardError => e
      puts "Error fetching OMDB poster for IMDB ID #{imdb_id}: #{e.message}"
      nil
    end
  end

  def validate_image_url(url, show_debug: false)
    return false if url.blank?

    begin
      uri = URI.parse(url)

      # Only check HTTP/HTTPS URLs
      return false unless %w[http https].include?(uri.scheme)

      puts "     🌐 Testing: #{uri.host}..." if show_debug

      # Make a HEAD request to check if the image exists without downloading it
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = 5  # Reduced to 5 seconds for faster processing
      http.open_timeout = 5

      request = Net::HTTP::Head.new(uri.request_uri)
      response = http.request(request)

      # Check if response is successful and content type is an image
      is_valid = response.code.to_i == 200 && response['content-type']&.start_with?('image/')

      if show_debug
        puts "     📊 Response: #{response.code} | Content-Type: #{response['content-type']}"
        puts "     #{is_valid ? '✅' : '❌'} Result: #{is_valid ? 'Valid' : 'Invalid'}"
      end

      is_valid

    rescue StandardError => e
      puts "     💥 Error: #{e.message}" if show_debug
      puts "Error validating image URL #{url}: #{e.message}" unless show_debug
      false
    end
  end
end
