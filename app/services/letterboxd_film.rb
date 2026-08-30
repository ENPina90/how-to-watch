# frozen_string_literal: true

# Builds links to a film on Letterboxd from the ids an Entry already carries.
#
# Letterboxd resolves /imdb/<id>/ and /tmdb/<id>/ to the canonical film page with a 302,
# so nothing here needs the film's slug -- which is just as well, since the app never
# learns it. IMDb is preferred only because more entries have one; either works.
module LetterboxdFilm
  BASE_URL = 'https://letterboxd.com'

  # Appended to a film URL to open Letterboxd's review prompt for it. Signed out this
  # path answers 403 exactly as an unknown path does, so it could not be confirmed from
  # outside a logged-in session; it is a constant so correcting it is a one-line change.
  REVIEW_SUFFIX = 'review'

  module_function

  # The film's page on Letterboxd, or nil when the entry carries no id to resolve it by.
  def film_url(imdb: nil, tmdb: nil)
    if imdb.present?
      "#{BASE_URL}/imdb/#{imdb}/"
    elsif tmdb.present?
      "#{BASE_URL}/tmdb/#{tmdb}/"
    end
  end

  # The film's page with Letterboxd's review prompt open.
  def review_url(imdb: nil, tmdb: nil)
    base = film_url(imdb: imdb, tmdb: tmdb)
    "#{base}#{REVIEW_SUFFIX}/" if base
  end
end
