# frozen_string_literal: true

require 'net/http'

# Builds links to a film on Letterboxd from what an Entry knows about it.
#
# Letterboxd has two ways to name a film. `/imdb/<id>/` and `/tmdb/<id>/` are lookup
# shortcuts that 302 to the real page; `/film/<slug>/` *is* the real page. The difference
# matters because only the canonical form accepts a trailing action: `/film/<slug>/review/`
# opens the review prompt, while `/imdb/<id>/review/` is just an unknown path -- the
# shortcut redirects the film, not the path hanging off it.
#
# So the review link needs the slug. The diary feed hands it over for free; for any other
# entry it is resolved once by reading where the shortcut redirects to, and kept.
module LetterboxdFilm
  BASE_URL = 'https://letterboxd.com'

  # Appended to a canonical film URL to open Letterboxd's review prompt.
  REVIEW_SUFFIX = 'review'

  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5

  # Slugs never change, so a resolved one is worth keeping even for entries with nowhere
  # to store it.
  SLUG_TTL = 30.days

  module_function

  # The lookup shortcut for a film. Always lands on the right page, but cannot carry an
  # action, so it is the fallback rather than the target.
  def lookup_url(imdb: nil, tmdb: nil)
    if imdb.present?
      "#{BASE_URL}/imdb/#{imdb}/"
    elsif tmdb.present?
      "#{BASE_URL}/tmdb/#{tmdb}/"
    end
  end

  def film_url(slug)
    "#{BASE_URL}/film/#{slug}/" if slug.present?
  end

  # The review prompt for a film whose slug is known.
  def review_url(slug)
    "#{film_url(slug)}#{REVIEW_SUFFIX}/" if slug.present?
  end

  # Where the button should actually send someone. Prefers the review prompt and falls
  # back to the film's page, which is one further click to the same place -- better than
  # a 404 when Letterboxd cannot be reached or has no such film.
  def best_url(slug: nil, imdb: nil, tmdb: nil)
    review_url(slug) || lookup_url(imdb: imdb, tmdb: tmdb)
  end

  # Reads the slug out of the shortcut's redirect. One request, cached, and never made
  # while rendering a page -- see LetterboxdController#review, which does this at click
  # time for the one film being opened.
  def resolve_slug(imdb: nil, tmdb: nil)
    url = lookup_url(imdb: imdb, tmdb: tmdb)
    return nil unless url

    Rails.cache.fetch(['letterboxd-slug', imdb, tmdb], expires_in: SLUG_TTL) do
      slug_from_redirect(url)
    end
  end

  def slug_from_redirect(url)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                               open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      # Letterboxd answers a bare Net::HTTP agent with 403.
      http.request(Net::HTTP::Get.new(uri, 'User-Agent' => 'HowToWatch/1.0 (+https://howtowatch.app)'))
    end

    return nil unless response.is_a?(Net::HTTPRedirection)

    response['location'].to_s[%r{/film/([^/]+)/}, 1]
  rescue Timeout::Error, SystemCallError, IOError, OpenSSL::SSL::SSLError, URI::Error => e
    # The caller falls back to the lookup URL, which needs no network to build.
    Rails.logger.warn("Letterboxd slug lookup failed for #{url}: #{e.class}: #{e.message}")
    nil
  end
end
