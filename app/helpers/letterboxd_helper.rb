# frozen_string_literal: true

module LetterboxdHelper
  # Letterboxd catalogues films, so the link is offered on movies only, and only where
  # there is something to find the film by. The single guard the button partial leans on.
  def letterboxd_reviewable?(entry)
    entry.media == 'movie' &&
      (entry.letterboxd_slug.present? || entry.imdb.present? || entry.tmdb.present?)
  end

  # Letterboxd's half-star rating as filled and empty stars. Returns nil when the entry
  # has no score, which is how the card decides not to show the row at all.
  def letterboxd_stars(score)
    return if score.blank?

    filled = (score.to_f / 0.5).round * 0.5
    full = filled.floor
    half = filled - full >= 0.5

    safe_join([
      *Array.new(full) { tag.i(class: 'fa-solid fa-star') },
      (tag.i(class: 'fa-solid fa-star-half-stroke') if half),
      *Array.new(5 - full - (half ? 1 : 0)) { tag.i(class: 'fa-regular fa-star') }
    ].compact)
  end
end
