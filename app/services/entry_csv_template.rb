# frozen_string_literal: true

require 'csv'

# The blank spreadsheet the custom-entry page hands out, and the definition of what its
# importer reads back. One list of columns for both, so a template can never describe a
# shape EntryCsvImporter does not accept.
#
# Deliberately not every Entry column. What is here is what somebody typing a row from
# scratch needs -- a name, where it plays from, how long it runs -- plus the two ids that
# let the importer fill the rest in from the APIs. The columns the app works out for itself
# (position, trailer, letterboxd_slug, the per-user tables) are nobody's business in a
# spreadsheet.
class EntryCsvTemplate
  # In the order they appear in the sheet, which is roughly the order a person fills them:
  # what it is, then where it plays from, then the trimmings.
  COLUMNS = %w[
    channel
    name
    media
    imdb
    tmdb
    year
    length
    source_url
    pic
    series
    season
    episode
    category
    genre
    rating
    director
    writer
    actors
    plot
    note
    review
  ].freeze

  # The media values the app actually renders. `entries/entry_#{media}` is a partial name,
  # so anything outside this set is an entry whose card cannot be drawn.
  MEDIA = %w[movie series anime episode fanedit].freeze

  # CSV has one sheet and no data validation, so the choices cannot be attached to the
  # `channel` cells themselves. They ride along in columns off to the right instead, which
  # is enough to point a Google Sheets validation rule at -- or to copy from. The importer
  # ignores any column it does not know, these two included.
  REFERENCE_COLUMNS = %w[available_channels available_media].freeze

  # Enough to type into without having to add rows, and short enough that the sheet still
  # reads as a blank form.
  BLANK_ROWS = 10

  def initialize(lists)
    @channels = lists.map(&:name).sort_by(&:downcase)
  end

  def generate
    CSV.generate do |csv|
      csv << COLUMNS + REFERENCE_COLUMNS
      rows.each { |row| csv << row }
    end
  end

  def self.filename_for(list) = "#{list.name.parameterize.presence || 'channel'}-entries-template.csv"

  private

    # The data columns stay empty -- it is a template, and a channel typed into every row
    # by default is a row that looks filled in when it is not. A blank `channel` means the
    # channel the file is uploaded to, which is the common case anyway.
    def rows
      Array.new([BLANK_ROWS, @channels.size, MEDIA.size].max) do |i|
        Array.new(COLUMNS.size) + [@channels[i], MEDIA[i]]
      end
    end
end
