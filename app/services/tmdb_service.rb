require 'net/http'
require 'json'

class TmdbService
  BASE_URL = 'https://api.themoviedb.org/3'
  IMAGE_BASE_URL = 'https://image.tmdb.org/t/p/w500'
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  # Show, season and episode metadata is effectively immutable; the player page and
  # watch_now both re-request the same episode every time they render.
  CACHE_TTL = 12.hours

  # Raised when TMDB cannot be reached or answers with something unparseable. Callers that
  # can carry on without the data rescue it; importers turn it into a user-facing message.
  class RequestError < StandardError; end

  # Single source of truth for the TMDB key, server side. Deliberately `fetch`: a missing
  # key should fail loudly instead of silently falling back to a hardcoded one.
  def self.api_key
    ENV.fetch('TMDB_API_KEY')
  end

  # --- Typed endpoints -------------------------------------------------------------
  # These replace the hand-rolled URI.open calls that used to live in the controllers.
  # Everything funnels through #get_json, so timeouts and error handling are in one place
  # (and caching, when it is added, will be too).

  def fetch_show(tmdb_id)
    get_json("tv/#{tmdb_id}")
  end

  def fetch_season(tmdb_id, season_number)
    get_json("tv/#{tmdb_id}/season/#{season_number}")
  end

  def fetch_episode(tmdb_id, season_number, episode_number)
    get_json("tv/#{tmdb_id}/season/#{season_number}/episode/#{episode_number}")
  end

  def fetch_show_external_ids(tmdb_id)
    get_json("tv/#{tmdb_id}/external_ids")
  end

  def fetch_episode_external_ids(tmdb_id, season_number, episode_number)
    get_json("tv/#{tmdb_id}/season/#{season_number}/episode/#{episode_number}/external_ids")
  end

  def find_by_imdb_id(imdb_id)
    get_json("find/#{imdb_id}", external_source: 'imdb_id')
  end

  def fetch_images(tmdb_id, media_type = 'movie')
    get_json("#{media_type}/#{tmdb_id}/images")
  end

  # Full URL for a TMDB image path, or nil when the payload had none.
  def self.image_url(path)
    return nil if path.blank?

    "#{IMAGE_BASE_URL}#{path}"
  end

  def fetch_imdb_id(tmdb_id, type = 'movie')
    path = case type
           when 'movie' then "movie/#{tmdb_id}"
           when 'show'  then "tv/#{tmdb_id}/external_ids"
           else raise ArgumentError, "Invalid type. Must be 'movie' or 'show'."
           end

    get_json(path)['imdb_id']
  rescue RequestError => e
    Rails.logger.error "Error fetching IMDb ID: #{e.message}"
    nil
  end

  def fetch_trailer_url(entry)
    return nil unless entry.tmdb

    videos = get_json("movie/#{entry.tmdb}/videos")['results'] || []
    trailer = videos.find { |video| video['type'] == 'Trailer' && video['site'] == 'YouTube' }

    return "https://www.youtube.com/watch?v=#{trailer['key']}" if trailer && trailer['key']

    Rails.logger.info "No trailer found for Entry ##{entry.id}"
    nil
  rescue RequestError => e
    Rails.logger.error "Error fetching trailer for Entry ##{entry.id}: #{e.message}"
    nil
  end

  def fetch_poster_url(tmdb_id, media_type = 'movie')
    return nil unless tmdb_id

    path = %w[tv show episode].include?(media_type) ? "tv/#{tmdb_id}" : "movie/#{tmdb_id}"
    poster_url = self.class.image_url(get_json(path)['poster_path'])

    Rails.logger.info "No poster found for TMDB ID: #{tmdb_id}" if poster_url.nil?
    poster_url
  rescue RequestError => e
    Rails.logger.error "Error fetching poster for TMDB ID #{tmdb_id}: #{e.message}"
    nil
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
          Rails.logger.info "OMDB poster URL is not accessible for IMDB ID: #{imdb_id}"
          nil
        end
      else
        Rails.logger.info "No poster found in OMDB for IMDB ID: #{imdb_id}"
        nil
      end

    rescue StandardError => e
      Rails.logger.error "Error fetching OMDB poster for IMDB ID #{imdb_id}: #{e.message}"
      nil
    end
  end

  # Single place where a TMDB request is actually made. Raises RequestError so callers
  # decide what a failure means; the older methods above keep their nil-on-error contract.
  def get_json(path, **query)
    Rails.cache.fetch(cache_key(path, query), expires_in: CACHE_TTL) { request_json(path, query) }
  end

  def validate_image_url(url, show_debug: false)
    return false if url.blank?

    begin
      uri = URI.parse(url)

      # Only check HTTP/HTTPS URLs
      return false unless %w[http https].include?(uri.scheme)

      Rails.logger.info "     🌐 Testing: #{uri.host}..." if show_debug

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
        Rails.logger.info "     📊 Response: #{response.code} | Content-Type: #{response['content-type']}"
        Rails.logger.info "     #{is_valid ? '✅' : '❌'} Result: #{is_valid ? 'Valid' : 'Invalid'}"
      end

      is_valid

    rescue StandardError => e
      Rails.logger.info "     💥 Error: #{e.message}" if show_debug
      Rails.logger.error "Error validating image URL #{url}: #{e.message}" unless show_debug
      false
    end
  end

  private

  def cache_key(path, query)
    # The api key is added at request time, so it never lands in a cache key.
    ['tmdb', path, query.sort.to_h].join(':')
  end

  # A raised RequestError propagates out of Rails.cache.fetch without being cached, so a
  # blip is retried on the next call rather than remembered for 12 hours.
  def request_json(path, query)
    uri = URI("#{BASE_URL}/#{path}")
    uri.query = URI.encode_www_form(query.merge(api_key: self.class.api_key))

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                               open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end

    raise RequestError, "TMDB #{path} returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise RequestError, "TMDB #{path} returned unparseable JSON: #{e.message}"
  rescue Timeout::Error, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
    raise RequestError, "TMDB #{path} failed: #{e.class}: #{e.message}"
  end

end
