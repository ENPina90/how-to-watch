require 'open-uri'
require 'nokogiri'

class UrlCheckerService
  def initialize(url)
    @url = prepare_url(url)
  end

  def valid_source?
    return false if @url.nil?

    response_body = URI.open(@url).read
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
    document = Nokogiri::HTML(response_body)
    title_text = document.at_css('title')&.text
    !title_text.nil? && !title_text.strip.empty?
  end
end
