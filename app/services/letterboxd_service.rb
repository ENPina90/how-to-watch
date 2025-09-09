require 'net/http'
require 'json'
require 'uri'

class LetterboxdService
  BASE_URL = 'https://api.letterboxd.com/api/v0'

  def initialize
    @client_id = ENV['LETTERBOXD_CLIENT_ID']
    @client_secret = ENV['LETTERBOXD_CLIENT_SECRET']
    @redirect_uri = ENV['LETTERBOXD_REDIRECT_URI'] || "#{Rails.application.routes.url_helpers.root_url}auth/letterboxd/callback"
  end

  # Step 1: Get authorization URL for user to authenticate with Letterboxd
  def authorization_url(state = nil)
    params = {
      response_type: 'code',
      client_id: @client_id,
      redirect_uri: @redirect_uri,
      scope: 'content:modify profile:private:view'
    }
    params[:state] = state if state

    "#{BASE_URL}/auth/authorize?" + URI.encode_www_form(params)
  end

  # Step 2: Exchange authorization code for access token
  def exchange_code_for_token(code)
    uri = URI("#{BASE_URL}/auth/token")

    params = {
      grant_type: 'authorization_code',
      client_id: @client_id,
      client_secret: @client_secret,
      code: code,
      redirect_uri: @redirect_uri
    }

    response = make_token_request(uri, params)

    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    else
      Rails.logger.error("Letterboxd token exchange failed: #{response.body}")
      nil
    end
  end

  # Step 3: Refresh access token
  def refresh_token(refresh_token)
    uri = URI("#{BASE_URL}/auth/token")

    params = {
      grant_type: 'refresh_token',
      client_id: @client_id,
      client_secret: @client_secret,
      refresh_token: refresh_token
    }

    response = make_token_request(uri, params)

    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    else
      Rails.logger.error("Letterboxd token refresh failed: #{response.body}")
      nil
    end
  end

  # Create a log entry (review) on Letterboxd
  def create_log_entry(access_token, film_id, options = {})
    uri = URI("#{BASE_URL}/log-entries")

    log_entry_data = {
      film: { id: film_id },
      watched: true,
      watchedDate: options[:watched_date] || Date.current.iso8601
    }

    # Add rating if provided (Letterboxd uses 0.5-5.0 scale, convert from 1-10)
    if options[:rating]
      letterboxd_rating = (options[:rating].to_f / 2.0).round(1)
      log_entry_data[:rating] = letterboxd_rating
    end

    # Add review text if provided
    log_entry_data[:review] = options[:review] if options[:review].present?

    # Add tags if provided
    log_entry_data[:tags] = options[:tags] if options[:tags].present?

    response = make_authenticated_request(uri, access_token, log_entry_data, :post)

    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    else
      Rails.logger.error("Letterboxd log entry creation failed: #{response.body}")
      {
        error: true,
        message: "Failed to create Letterboxd entry: #{response.body}",
        status: response.code
      }
    end
  end

  # Search for films on Letterboxd
  def search_films(access_token, query)
    uri = URI("#{BASE_URL}/search")
    uri.query = URI.encode_www_form({
      input: query,
      searchMethod: 'FullText',
      include: 'FilmSearchItem'
    })

    response = make_authenticated_request(uri, access_token, nil, :get)

    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    else
      Rails.logger.error("Letterboxd film search failed: #{response.body}")
      nil
    end
  end

  # Get film details by Letterboxd ID
  def get_film(access_token, film_id)
    uri = URI("#{BASE_URL}/film/#{film_id}")

    response = make_authenticated_request(uri, access_token, nil, :get)

    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    else
      Rails.logger.error("Letterboxd get film failed: #{response.body}")
      nil
    end
  end

  # Find Letterboxd film by IMDB ID
  def find_film_by_imdb(access_token, imdb_id)
    # Search using IMDB ID
    search_results = search_films(access_token, imdb_id)

    return nil unless search_results && search_results['items']

    # Look for exact IMDB match in results
    film_match = search_results['items'].find do |item|
      item['film'] && item['film']['links'] &&
      item['film']['links'].any? { |link| link['url']&.include?(imdb_id) }
    end

    film_match&.dig('film')
  end

  # Get user's profile information
  def get_user_profile(access_token)
    uri = URI("#{BASE_URL}/me")

    response = make_authenticated_request(uri, access_token, nil, :get)

    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    else
      Rails.logger.error("Letterboxd get profile failed: #{response.body}")
      nil
    end
  end

  # Sync user entry to Letterboxd
  def sync_user_entry_to_letterboxd(user_entry, access_token)
    return { error: true, message: "No access token provided" } unless access_token
    return { error: true, message: "Entry not completed" } unless user_entry.completed?

    entry = user_entry.entry

    # Try to find the film on Letterboxd
    letterboxd_film = if entry.imdb.present?
      find_film_by_imdb(access_token, entry.imdb)
    else
      # Fallback to search by name and year
      search_results = search_films(access_token, "#{entry.name} #{entry.year}")
      search_results&.dig('items', 0, 'film')
    end

    unless letterboxd_film
      return {
        error: true,
        message: "Could not find '#{entry.name}' on Letterboxd"
      }
    end

    # Prepare log entry options
    options = {
      watched_date: user_entry.completed_at&.to_date || Date.current,
      rating: user_entry.review,
      review: user_entry.comment
    }

    # Create the log entry
    result = create_log_entry(access_token, letterboxd_film['id'], options)

    if result[:error]
      result
    else
      {
        success: true,
        message: "Successfully logged '#{entry.name}' to Letterboxd",
        letterboxd_entry: result
      }
    end
  end

  private

  def make_token_request(uri, params)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request['Accept'] = 'application/json'
    request.body = URI.encode_www_form(params)

    http.request(request)
  end

  def make_authenticated_request(uri, access_token, data = nil, method = :get)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = case method
              when :post
                Net::HTTP::Post.new(uri)
              when :patch
                Net::HTTP::Patch.new(uri)
              when :delete
                Net::HTTP::Delete.new(uri)
              else
                Net::HTTP::Get.new(uri)
              end

    request['Authorization'] = "Bearer #{access_token}"
    request['Accept'] = 'application/json'

    if data && [:post, :patch].include?(method)
      request['Content-Type'] = 'application/json'
      request.body = data.to_json
    end

    http.request(request)
  end
end
