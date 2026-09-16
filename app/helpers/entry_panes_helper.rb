# frozen_string_literal: true

# What the Details tab on an entry card lists.
#
# The pane is fetched on demand rather than rendered into the card, so none of this is
# multiplied by the ~1,200 cards a big channel draws -- see CARD_PANES in
# card_panes_controller.js and `entries#panes` for why that matters here more than usual.
module EntryPanesHelper
  # What each card already prints above the plot. The pane is a place for what is *not* on
  # the card, so a field listed here is left out for that media type -- reading the same
  # year twice, once above the tabs and once below them, is how a details panel starts
  # looking like padding.
  ALREADY_ON_CARD = {
    'movie' => %i[year length rating genre language],
    'series' => %i[year rating genre],
    'anime' => %i[year rating genre],
    'episode' => %i[year length rating genre series season episode],
    'fanedit' => %i[length genre]
  }.freeze

  # Every field worth listing, in the order somebody reads them: who made it, then what it
  # is, then where it is filed. Labels are fixed here rather than humanized from the column
  # so `imdb` does not come out as "Imdb".
  DETAIL_FIELDS = [
    %i[director Director],
    %i[writer Writer],
    %i[actors Cast],
    %i[genre Genre],
    %i[language Language],
    %i[year Year],
    %i[length Runtime],
    %i[rating Rating],
    %i[series Series],
    %i[season Season],
    %i[episode Episode],
    %i[category Category],
    %i[franchise Franchise]
  ].freeze

  # Label/value pairs for one entry: everything present, minus what its own card shows.
  # Blank values are dropped rather than printed empty -- a hand-typed entry has most of
  # these missing, and a column of "—" says nothing.
  def entry_detail_rows(entry)
    skip = ALREADY_ON_CARD.fetch(entry.media.to_s, [])

    DETAIL_FIELDS.filter_map do |field, label|
      next if skip.include?(field)

      value = entry.public_send(field)
      next if value.blank?

      [label.to_s, field == :length ? "#{value} min" : value.to_s]
    end
  end

  # The catalogue links, which are ids on the row rather than facts about the film and so
  # read better as links than as a "tt0120915" nobody wants to copy out by hand.
  def entry_detail_links(entry)
    links = []
    links << ['IMDb', "https://www.imdb.com/title/#{entry.imdb}/"] if entry.imdb.to_s.match?(LetterboxdFilm::IMDB_FORMAT)
    letterboxd = LetterboxdFilm.film_url(entry.letterboxd_slug)
    links << ['Letterboxd', letterboxd] if letterboxd
    links
  end
end
