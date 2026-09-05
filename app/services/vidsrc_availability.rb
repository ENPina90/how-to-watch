# frozen_string_literal: true

require 'net/http'
require 'json'

# Asks VidSrc's data API whether it actually holds a given title (VIDSRC.md §4a).
#
# This is the only honest answer to "will this entry play". The embed URL is not: every
# front door returns 200 with the same 54KB shell whether or not there is anything behind
# it, and so does the shell's own /vs_src.php, which mints a signed URL either way. "This
# media is unavailable" is rendered by the innermost player after it asks this endpoint,
# which answers {"status_code":404} for a title it does not have.
#
# Three states, not two. :unknown is the important one -- if the API cannot be reached, or
# its host has rotated out from under us, every title would otherwise look missing and a
# sweep would report the entire catalogue as broken. Callers must treat :unknown as "not
# answered" and never as "unplayable".
class VidsrcAvailability
  # Discovered from the player chain on 2026-09-06. Not a domain the app controls and not
  # in any template, so it is written down here with #discover_host as the way back when it
  # rotates -- `vidsrcme` is on the provider's own at-risk list (VIDSRC.md §1).
  DEFAULT_HOST = 'data.vidsrcme.ru'
  # A title known to be present, used to tell "this host is dead" apart from "this title is
  # missing". Gladiator, the same probe VIDSRC.md §5 uses.
  PROBE_IMDB = 'tt0172495'

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 15
  CACHE_TTL = 6.hours

  Result = Struct.new(:state, :detail, keyword_init: true) do
    def missing? = state == :missing
    def unknown? = state == :unknown
  end

  def initialize(host: nil)
    @host = host
  end

  # What this entry would actually ask VidSrc for -- for a series that is one specific
  # episode, not the show. Public because the bulk screen in EmbedAvailabilityAudit has to
  # ask the same question of the ID dumps, and two answers to it would be two answers.
  Lookup = Struct.new(:type, :imdb, :season, :episode, keyword_init: true)

  # A Lookup, or a :unknown Result saying why there is nothing to ask about.
  def lookup_for(entry, subentry: nil)
    case entry.media
    when 'movie', 'fanedit'
      return unknown('entry has no imdb id') if entry.imdb.blank?

      Lookup.new(type: 'movie', imdb: entry.imdb)
    when 'series', 'anime', 'episode'
      season, episode = episode_numbers(entry, subentry)
      imdb = entry.series_imdb.presence || entry.imdb
      return unknown('no series imdb id') if imdb.blank?
      return unknown('no episode to play') if season.blank? || episode.blank?

      Lookup.new(type: 'tv', imdb: imdb, season: season, episode: episode)
    else
      unknown("media #{entry.media.inspect} is not a vidsrc kind")
    end
  end

  # :available / :missing / :unknown for one entry.
  def for_entry(entry, subentry: nil)
    lookup = lookup_for(entry, subentry: subentry)
    return lookup if lookup.is_a?(Result)

    query(type: lookup.type, imdb: lookup.imdb, season: lookup.season, episode: lookup.episode)
  end

  # True when the API is answering at all. A sweep should stop rather than report anything
  # if this is false: see the class comment.
  def reachable?
    query(type: 'movie', imdb: PROBE_IMDB).state == :available
  end

  private

  def episode_numbers(entry, subentry)
    return [entry.season, entry.episode] if entry.media == 'episode'

    playing = subentry || entry.current || entry.subentries.min_by { |s| [s.season.to_i, s.episode.to_i] }
    [playing&.season, playing&.episode]
  end

  def query(type:, imdb:, season: nil, episode: nil)
    params = { type: type, imdb: imdb }
    params[:season] = season if season
    params[:episode] = episode if episode

    body = Rails.cache.fetch("vidsrc_availability/#{params.values.join('/')}", expires_in: CACHE_TTL) do
      get(params)
    end
    return unknown('no answer') if body.nil?

    # The API is inconsistent about quoting: 404 comes back as a number, 200 as a string.
    code = JSON.parse(body)['status_code'].to_i
    case code
    when 200 then Result.new(state: :available)
    when 404 then Result.new(state: :missing, detail: 'VidSrc has no file for it')
    else unknown("answered status_code #{code}")
    end
  rescue JSON::ParserError => e
    unknown("unparseable answer: #{e.message}")
  end

  def get(params)
    uri = URI.parse("https://#{host}/api.php")
    uri.query = URI.encode_www_form(params)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      # The endpoint is reached from inside the player, and answers accordingly.
      http.request(Net::HTTP::Get.new(uri, 'Referer' => "https://#{host}/"))
    end

    response.code.to_i == 200 ? response.body : nil
  rescue StandardError => e
    Rails.logger.error "VidSrc availability request failed: #{e.class}: #{e.message}"
    nil
  end

  def unknown(detail) = Result.new(state: :unknown, detail: detail)

  def host = @host ||= DEFAULT_HOST
end
