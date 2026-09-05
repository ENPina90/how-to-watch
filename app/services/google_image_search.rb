# frozen_string_literal: true

require 'net/http'
require 'json'

# Google Programmable Search in image mode -- the last resort in the poster picker, for the
# titles the film databases have never heard of: fan edits, cuts, compilations, anything
# whose art only exists on somebody's blog.
#
# Off unless GOOGLE_SEARCH_API_KEY and GOOGLE_SEARCH_ENGINE_ID are both set. It is the one
# source in the picker needing credentials the app does not already have, and the free tier
# is 100 queries a day, so an unset key means "no web results" rather than an error.
#
# There is deliberately no Bing equivalent: Microsoft retired the Bing Search APIs in
# August 2025, so that door is closed rather than merely unopened.
class GoogleImageSearch
  ENDPOINT = 'https://www.googleapis.com/customsearch/v1'
  RESULT_COUNT = 6
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  # Reopening the picker on the same entry must not spend another of the day's 100 queries.
  CACHE_TTL = 12.hours

  def self.configured?
    ENV['GOOGLE_SEARCH_API_KEY'].present? && ENV['GOOGLE_SEARCH_ENGINE_ID'].present?
  end

  # [{ url:, host:, width:, height: }] in Google's own ranking.
  #
  # Never raises. This is the least trustworthy source in the picker and the one most
  # likely to be misconfigured, so a failure here costs nothing but its own results.
  def call(query, portrait_only: true)
    return [] if query.blank? || !self.class.configured?

    items = search(query)['items'] || []
    items.filter_map { |item| result_for(item, portrait_only) }
  rescue StandardError => e
    Rails.logger.error "Google image search failed for #{query.inspect}: #{e.class}: #{e.message}"
    []
  end

  private

  def search(query)
    Rails.cache.fetch("google_image_search/#{query}", expires_in: CACHE_TTL) { request(query) }
  end

  def request(query)
    uri = URI.parse(ENDPOINT)
    uri.query = URI.encode_www_form(
      key: ENV.fetch('GOOGLE_SEARCH_API_KEY'),
      cx: ENV.fetch('GOOGLE_SEARCH_ENGINE_ID'),
      q: query,
      searchType: 'image',
      num: RESULT_COUNT,
      safe: 'active'
    )

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end

    return {} unless response.code.to_i == 200

    JSON.parse(response.body)
  end

  def result_for(item, portrait_only)
    url = item['link']
    # http images are blocked as mixed content on the picker anyway, so an http result is
    # not a result.
    return nil if url.blank? || !url.start_with?('https://')

    image = item['image'] || {}
    width = image['width'].to_i
    height = image['height'].to_i

    # A poster is portrait. Image search returns a great many landscape banners, logos and
    # screengrabs, and offering those as posters is most of what makes a picker feel
    # random. Episodes are exempt: their art is a still, which is landscape.
    return nil if portrait_only && width.positive? && height.positive? && height < width

    { url: url, host: URI.parse(url).host, width: width, height: height }
  rescue URI::InvalidURIError
    nil
  end
end
