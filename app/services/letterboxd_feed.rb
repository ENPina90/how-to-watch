# frozen_string_literal: true

require 'net/http'
require 'nokogiri'

# Reads a member's public Letterboxd diary from their RSS feed.
#
# This is the whole Letterboxd integration. The official API is request-only and is not
# granted for personal projects, but every member profile publishes an unauthenticated
# feed at /<username>/rss/ carrying exactly what the sync needs: the film, the member's
# rating, and when they watched it. So "linking an account" is a username and nothing
# else -- no OAuth, no token, no callback.
#
# Two limits are inherent to the feed and are not bugs:
#   * it holds roughly the 100 most recent items, so it is a rolling window rather than
#     a member's full history;
#   * it identifies films by TMDB id only, so callers that need an IMDb id resolve it
#     themselves (see LetterboxdList, which uses the cached TmdbService lookup).
class LetterboxdFeed
  BASE_URL = 'https://letterboxd.com'
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  # Letterboxd usernames are alphanumeric with underscores. Anchored and applied before
  # the username reaches a URL, so a name can never walk out of the /<name>/rss/ path --
  # this endpoint is reachable while signed out, from the sign-up form.
  USERNAME_FORMAT = /\A[a-z0-9_]{1,32}\z/i

  # Declared on the feed's <rss> element.
  NAMESPACES = {
    'letterboxd' => 'https://letterboxd.com',
    'tmdb' => 'https://themoviedb.org'
  }.freeze

  # Diary entries carry this guid prefix; lists and stories share the feed and do not.
  WATCH_GUID_PREFIX = 'letterboxd-watch-'

  # Letterboxd closes every diary description with this, review or no review.
  WATCHED_ON_SENTENCE = /\AWatched on .*\.\z/

  # A diary link is /<member>/film/<slug>/, with a numeric suffix on a rewatch. The
  # slug is the only form of the film URL that accepts /review/, so it is worth taking
  # here rather than resolving later with a request per film.
  FILM_SLUG = %r{/[^/]+/film/([^/]+)/}

  class RequestError < StandardError; end

  # A single diary entry. `rating` is Letterboxd's own 0.5-5.0 half-star scale, and is
  # nil for an unrated watch -- which is ordinary, not an error.
  Watch = Struct.new(
    :guid, :tmdb_id, :title, :year, :rating, :watched_on,
    :rewatch, :poster_url, :review, :url, :slug,
    keyword_init: true
  ) do
    def rewatch? = rewatch
  end

  def self.valid_username?(username)
    username.to_s.match?(USERNAME_FORMAT)
  end

  def initialize(username)
    @username = username.to_s
  end

  attr_reader :username

  # Every diary entry in the feed, newest first. Raises RequestError if the feed cannot
  # be reached or is not a Letterboxd feed; returns [] for a real but empty diary.
  def watches
    @watches ||= parse(fetch)
  end

  # Does this name belong to a real member with a readable diary? Used by the sign-up and
  # profile forms to tell a wrong username from a display name. A private profile has no
  # public feed, so it answers false here the same as a name that does not exist -- from
  # outside, the two are indistinguishable.
  def readable?
    watches.any?
  rescue RequestError
    false
  end

  private

  def fetch
    raise RequestError, "#{username.inspect} is not a valid Letterboxd username" unless self.class.valid_username?(username)

    uri = URI("#{BASE_URL}/#{username}/rss/")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                               open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      # Letterboxd serves the feed to anyone, but answers 403 to a bare Net::HTTP agent.
      http.request(Net::HTTP::Get.new(uri, 'User-Agent' => 'HowToWatch/1.0 (+https://howtowatch.app)'))
    end

    raise RequestError, "Letterboxd feed for #{username} returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  rescue Timeout::Error, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
    raise RequestError, "Letterboxd feed for #{username} failed: #{e.class}: #{e.message}"
  end

  def parse(body)
    doc = Nokogiri::XML(body)
    raise RequestError, "Letterboxd feed for #{username} was unparseable" if doc.root.nil?

    doc.xpath('//item').filter_map { |item| build_watch(item) }
  end

  # Returns nil for anything in the feed that is not a diary entry, or for a diary entry
  # with no TMDB id -- there is nothing to match such a film against.
  def build_watch(item)
    guid = text(item, 'guid')
    return unless guid&.start_with?(WATCH_GUID_PREFIX)

    tmdb_id = text(item, 'tmdb:movieId')
    return if tmdb_id.blank?

    description = text(item, 'description').to_s
    link = text(item, 'link')

    Watch.new(
      guid: guid,
      tmdb_id: tmdb_id,
      title: text(item, 'letterboxd:filmTitle'),
      year: text(item, 'letterboxd:filmYear')&.to_i,
      rating: text(item, 'letterboxd:memberRating')&.to_f,
      watched_on: parse_date(text(item, 'letterboxd:watchedDate')),
      rewatch: text(item, 'letterboxd:rewatch') == 'Yes',
      poster_url: poster_from(description),
      review: review_from(description),
      url: link,
      slug: link&.[](FILM_SLUG, 1)
    )
  end

  def text(item, path)
    node = item.at_xpath(path, NAMESPACES)
    value = node&.text&.strip
    value.presence
  end

  def parse_date(value)
    Date.parse(value) if value.present?
  rescue Date::Error
    nil
  end

  # The description is a poster <img>, then the review if there is one, then a closing
  # "Watched on <date>." sentence. Only the middle is the member's own writing.
  def review_from(description)
    fragment = Nokogiri::HTML.fragment(description)
    fragment.css('img').remove

    paragraphs = fragment.css('p').map { |p| p.text.strip }.reject(&:blank?)
    paragraphs.reject { |p| p.match?(WATCHED_ON_SENTENCE) }.join("\n\n").presence
  end

  def poster_from(description)
    Nokogiri::HTML.fragment(description).at_css('img')&.[]('src')
  end
end
