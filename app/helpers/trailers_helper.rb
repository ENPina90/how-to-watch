# frozen_string_literal: true

module TrailersHelper
  # The line under a trailer's title: when the film is from, how long it runs, and what kind
  # of film it is. Three genres at most -- the card sits over the picture, and a run of six
  # is a paragraph.
  def trailer_facts(entry)
    genres = entry.genre.to_s.split(',').map(&:strip).compact_blank.first(3).join(', ')

    [entry.year, cable_runtime_label(entry.length), genres.presence].compact_blank.join(' · ')
  end
end
