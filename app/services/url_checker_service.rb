require 'open-uri'
require 'nokogiri'
require 'timeout'

class UrlCheckerService
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5
  # open/read timeouts apply per operation, so a host that trickles bytes or
  # redirects can still stall well past them. This caps the whole check.
  TOTAL_TIMEOUT = 8
  # The <title> lives in <head>, so there is no reason to pull down the whole page.
  MAX_BYTES = 64 * 1024

  def initialize(url)
    @url = prepare_url(url)
  end

  def valid_source?
    return false if @url.nil?

    response_body = Timeout.timeout(TOTAL_TIMEOUT) do
      URI.open(@url, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |body|
        body.read(MAX_BYTES)
      end
    end
    check_title(response_body)
  rescue StandardError => e
    Rails.logger.error("Error checking source: #{e.message}")
    false
  end

  private

  def prepare_url(url)
    return if url.nil?

    uri = URI.parse(url)
    uri = URI.parse("http://#{url}") if uri.scheme.nil?
    uri.to_s
  rescue URI::InvalidURIError => e
    Rails.logger.error("Invalid URI: #{e.message}")
    nil
  end

  def check_title(response_body)
    document = Nokogiri::HTML(response_body.to_s)
    title_text = document.at_css('title')&.text
    !title_text.nil? && !title_text.strip.empty?
  end
end
