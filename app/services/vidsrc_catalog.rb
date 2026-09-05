# frozen_string_literal: true

require 'net/http'

# VidSrc's daily ID dumps: every imdb id it can play, as three flat files (VIDSRC.md §8).
#
# These exist for scale. Asking the per-title API about all 3,513 entries would be 3,513
# requests; the dumps answer the same question for the whole catalogue in three.
#
# They are a screen, not a verdict. Measured 2026-09-06 against the data API, one entry in
# eight that the dumps called missing turned out to be playable -- a film carried only under
# its series, most likely. So a miss here means "ask VidsrcAvailability about this one",
# never "broken"; EmbedAvailabilityAudit is what puts the two together.
class VidsrcCatalog
  MOVIES = 'movie_imdb.txt'
  SHOWS = 'tv_imdb.txt'
  EPISODES = 'eps_imdb.txt'

  # Regenerated daily at their end, and the episode dump is ~7.5MB, so this is cached for
  # long enough that a sweep and the rake task behind it share one download.
  CACHE_TTL = 12.hours
  OPEN_TIMEOUT = 5
  # The episode dump is megabytes, not kilobytes.
  READ_TIMEOUT = 90

  class Unavailable < StandardError; end

  def movie?(imdb) = imdb.present? && ids(MOVIES).include?(imdb)
  def show?(imdb) = imdb.present? && ids(SHOWS).include?(imdb)

  # Keyed "tt0041038_1x1" -- imdb, season, episode, no zero padding.
  def episode?(imdb, season, episode)
    return false if imdb.blank? || season.blank? || episode.blank?

    ids(EPISODES).include?("#{imdb}_#{season.to_i}x#{episode.to_i}")
  end

  # Every dump downloaded and parsed, so a caller can fail before doing any work rather
  # than treating an empty set as "VidSrc can play nothing".
  def warm!
    [MOVIES, SHOWS, EPISODES].each { |file| ids(file) }
    self
  end

  def sizes = [MOVIES, SHOWS, EPISODES].to_h { |file| [file, ids(file).size] }

  private

  def ids(file)
    @ids ||= {}
    @ids[file] ||= Set.new(fetch(file))
  end

  def fetch(file)
    Rails.cache.fetch("vidsrc_catalog/#{file}", expires_in: CACHE_TTL) do
      body = get("https://#{host}/ids/#{file}")
      lines = body.split("\n").map(&:strip).reject(&:empty?)
      # An empty or truncated dump would read as "VidSrc can play nothing", which would
      # flag the entire catalogue. Refuse it instead.
      raise Unavailable, "#{file} came back with #{lines.size} ids" if lines.size < 1_000

      lines
    end
  end

  def get(url)
    uri = URI.parse(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end
    raise Unavailable, "#{url} answered #{response.code}" unless response.code.to_i == 200

    response.body
  rescue StandardError => e
    raise Unavailable, "#{url}: #{e.class}: #{e.message}"
  end

  # Read off the source templates rather than written down here. Every vidsrc front door
  # serves the same dumps, and VIDSRC.md §1a is about what happens to a vidsrc host that
  # lives somewhere the templates do not reach.
  def host
    @host ||= begin
      source = Source.vidsrc_front_door
      raise Unavailable, 'No active vidsrc provider to ask' if source.nil?

      source.host or raise Unavailable, "#{source.slug} has no usable template host"
    end
  end
end
