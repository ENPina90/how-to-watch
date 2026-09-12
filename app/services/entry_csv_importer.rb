# frozen_string_literal: true

require 'csv'

# Reads the sheet EntryCsvTemplate handed out and adds its rows to a channel.
#
# Two kinds of row, and the difference is whether an `imdb` id is filled in. With one, the
# id is looked up and whatever the sheet says wins over whatever the API said -- which is
# the whole point of typing a row by hand about a film the API already knows: a fanedit's
# runtime, a corrected title, a poster that is not the theatrical one. Without one, the row
# is all there is and becomes a custom entry.
#
# Runs inside the request rather than in a job, so the person who uploaded the file is told
# what happened to every row while they are still looking at the page. That is what MAX_ROWS
# is for: each row carrying an id is an OMDB round trip, and a thousand of them would be a
# request nobody is still waiting for.
class EntryCsvImporter
  MAX_ROWS = 200

  # 5MB of CSV is far more than MAX_ROWS of it. The cap is on reading a file that was never
  # a spreadsheet into memory to find that out.
  MAX_BYTES = 5.megabytes

  Result = Struct.new(:created, :skipped, :errors, keyword_init: true) do
    def summary
      parts = ["#{created.size} #{'entry'.pluralize(created.size)} added"]
      parts << "#{skipped.size} skipped" if skipped.any?
      parts << "#{errors.size} #{'row'.pluralize(errors.size)} failed" if errors.any?
      parts.join(', ')
    end

    def any_problems? = skipped.any? || errors.any?
  end

  # `user` decides which channels a `channel` cell is allowed to name: without it, a sheet
  # could file rows into somebody else's channel by typing its name.
  def initialize(file:, list:, user:)
    @file = file
    @list = list
    @user = user
    @created = []
    @skipped = []
    @errors = []
  end

  def call
    rows = parse
    return rows if rows.is_a?(Result) # parse failed outright

    rows.each_with_index { |row, index| import(row, index + 2) } # +2: header is line 1

    result
  end

  private

    def parse
      return failure('No file was chosen') if @file.blank?

      content = @file.read
      return failure("That file is over #{MAX_BYTES / 1.megabyte}MB") if content.bytesize > MAX_BYTES

      # Sheets exported from Excel arrive with a BOM, which would otherwise become part of
      # the first header's name and leave `channel` unreadable.
      table = CSV.parse(content.sub("\xEF\xBB\xBF".dup.force_encoding('UTF-8'), ''), headers: true, header_converters: ->(h) { h.to_s.strip.downcase })
      return failure('That file has no header row') if table.headers.compact.empty?

      rows = table.map(&:to_h)
      return failure("That file has #{rows.size} rows; #{MAX_ROWS} is the most one upload can take") if rows.size > MAX_ROWS

      rows
    rescue CSV::MalformedCSVError => e
      failure("That file could not be read as CSV: #{e.message}")
    rescue ArgumentError, EncodingError
      failure('That file is not text — export it as CSV rather than as a spreadsheet')
    end

    def import(row, line)
      values = row.transform_values { |value| value.to_s.strip.presence }
      return if blank_row?(values)

      list = target_list(values['channel'])
      return @errors << "Line #{line}: no channel of yours is called “#{values['channel']}”" if list.nil?

      attributes = attributes_for(values)
      return @errors << "Line #{line}: a name is needed (or an imdb id the lookup can find one from)" if attributes[:name].blank?

      existing = duplicate_in(list, attributes)
      return @skipped << "Line #{line}: #{attributes[:name]} is already in #{list.name}" if existing

      create(list, attributes, line)
    end

    # Everything empty but the reference columns, which every row of the blank template
    # carries. Those are not data and a row holding nothing else is not a row.
    def blank_row?(values)
      EntryCsvTemplate::COLUMNS.none? { |column| values[column].present? }
    end

    def target_list(name)
      return @list if name.blank?
      return @list if name.casecmp?(@list.name)

      editable_lists.find { |list| list.name.casecmp?(name) }
    end

    def editable_lists
      @editable_lists ||= @user.admin? ? List.all.to_a : @user.lists.to_a
    end

    # The sheet over the API, field by field, so a row can correct one thing without
    # restating the rest. Compacted before the merge, not after: an empty cell has to leave
    # the API's answer standing, and merging a nil over it and tidying up afterwards throws
    # that answer away instead.
    def attributes_for(values)
      from_api(values['imdb'], values['media'])
        .compact
        .merge(from_sheet(values).compact)
    end

    def from_sheet(values)
      {
        name:        values['name'],
        media:       media_for(values['media']),
        imdb:        values['imdb'],
        tmdb:        values['tmdb'],
        year:        values['year']&.to_i,
        length:      values['length']&.to_i,
        source_url:  values['source_url'],
        pic:         values['pic'],
        series:      values['series'],
        season:      values['season']&.to_i,
        episode:     values['episode']&.to_i,
        category:    values['category'],
        genre:       values['genre'],
        rating:      values['rating']&.to_f,
        director:    values['director'],
        writer:      values['writer'],
        actors:      values['actors'],
        plot:        values['plot'],
        note:        values['note'],
        review:      values['review']
      }
    end

    # Unknown media is left nil rather than raised on: the default below catches it, and a
    # typo in one cell should not be the reason a row of real data is thrown away.
    def media_for(media)
      media && EntryCsvTemplate::MEDIA.find { |known| known.casecmp?(media) }
    end

    def from_api(imdb, media)
      return default_media(media) if imdb.blank?

      result = OmdbApi.get_movie(imdb)
      return default_media(media) if result.nil?

      attributes = OmdbApi.normalize_omdb_data(result)
      attributes.delete(:pic) if attributes[:pic].blank? || attributes[:pic] == 'N/A'
      # OMDB has no idea which of its "series" are anime; the sheet does.
      attributes[:media] = 'anime' if media_for(media) == 'anime'
      attributes
    end

    # What a row with nothing but a name is. `fanedit` rather than `movie` because that is
    # what this page is for -- a cut, a rip or a home recording with no id behind it -- and
    # it matches what the form beside it defaults to.
    def default_media(media) = { media: media_for(media) || 'fanedit' }

    # Same two questions the rest of the app asks: the id if there is one, the name
    # otherwise. `series` is in the name scope because the Entry uniqueness validation puts
    # it there -- two shows can each have an episode called "Pilot".
    def duplicate_in(list, attributes)
      # An episode is filed under its *series'* imdb id, so matching on that would call the
      # second episode of a show a duplicate of the first. Episodes go by name.
      if attributes[:imdb].present? && attributes[:media] != 'episode'
        return list.entries.find_by(imdb: attributes[:imdb])
      end

      list.entries.find_by(name: attributes[:name], series: attributes[:series])
    end

    def create(list, attributes, line)
      entry = Entry.new(attributes.merge(list: list, position: Entry.next_position(list)))

      if entry.save
        @created << entry
      else
        @errors << "Line #{line}: #{entry.name.presence || 'that row'} — #{entry.errors.full_messages.to_sentence}"
      end
    rescue StandardError => e
      Rails.logger.error "CSV import failed on line #{line} of a file for list #{list.id}: #{e.class}: #{e.message}"
      @errors << "Line #{line}: #{e.message}"
    end

    def result = Result.new(created: @created, skipped: @skipped, errors: @errors)

    def failure(message) = Result.new(created: [], skipped: [], errors: [message])
end
