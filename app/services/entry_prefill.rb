# frozen_string_literal: true

# Builds an *unsaved* Entry from what TMDB and OMDB know about a title, so the custom-entry
# form can open already filled in.
#
# The point of it is what it does not do. The search overlay's + buttons post to
# EntriesController#create and the row exists before anybody has looked at it; the same
# result's "+ Details" button comes here instead. A fanedit, a personal cut, a rip with its
# own runtime -- anything the APIs describe badly or only halfway -- can be corrected while
# it is still a form, and abandoned by navigating away.
#
# Returns a Result whose `entry` is always an Entry, prefilled or blank: a lookup that comes
# back empty is a reason to say so in a flash, not a reason to refuse to draw the form.
class EntryPrefill
  Result = Struct.new(:entry, :error, keyword_init: true)

  def initialize(list:, imdb: nil, tmdb: nil, season: nil, episode: nil, type: nil, tmdb_service: nil)
    @list = list
    @imdb = imdb.presence
    @tmdb = tmdb.presence
    @season = season.presence
    @episode = episode.presence
    @type = type.presence
    @tmdb_service = tmdb_service
  end

  def call
    return Result.new(entry: blank_entry) unless prefilling?

    standalone_episode? ? from_tmdb_episode : from_omdb
  rescue StandardError => e
    # A form is more use than a 500. The APIs are third parties and this is the one place a
    # page exists purely to be typed into by hand.
    Rails.logger.error "Prefill failed for imdb=#{@imdb} tmdb=#{@tmdb}: #{e.class}: #{e.message}"
    Result.new(entry: blank_entry, error: 'Could not reach the metadata service — the form is blank.')
  end

  private

    # Only the shape the search overlay sends. Anything else draws the blank form rather
    # than guessing at what was meant.
    def prefilling? = @imdb.present? || (@tmdb.present? && standalone_episode?)

    # An episode is the one case OMDB cannot answer from the id the overlay has: the card
    # carries the *series'* imdb id, and `get_movie` on that describes the series. TMDB is
    # asked for the episode itself, exactly as EpisodeImporter does.
    def standalone_episode? = @season.present? && @episode.present? && @tmdb.present?

    def from_omdb
      result = OmdbApi.get_movie(@imdb)
      return Result.new(entry: blank_entry(imdb: @imdb, tmdb: @tmdb), error: 'Nothing found for that id — the form is blank.') if result.nil?

      attributes = OmdbApi.normalize_omdb_data(result)
      attributes[:tmdb] = @tmdb
      # The search tab is the only thing that knows an anime from a series: OMDB files both
      # under Type "series".
      attributes[:media] = 'anime' if @type == 'anime'

      Result.new(entry: build(attributes))
    end

    def from_tmdb_episode
      service = @tmdb_service || TmdbService.new
      show = service.fetch_show(@tmdb)
      episode = service.fetch_episode(@tmdb, @season.to_i, @episode.to_i)
      return Result.new(entry: blank_entry(imdb: @imdb, tmdb: @tmdb), error: 'TMDB had nothing for that episode — the form is blank.') if show.nil? || episode.nil?

      Result.new(entry: build(
        media:       'episode',
        name:        "#{show['name']} - #{episode['name']}",
        series:      show['name'],
        series_imdb: @imdb,
        imdb:        @imdb,
        tmdb:        @tmdb,
        season:      @season.to_i,
        episode:     @episode.to_i,
        plot:        episode['overview'],
        pic:         TmdbService.image_url(episode['still_path']),
        rating:      episode['vote_average'],
        length:      episode['runtime'],
        year:        episode['air_date'].to_s[0, 4].presence&.to_i
      ))
    end

    def build(attributes)
      # `pic` of 'N/A' is OMDB's way of saying it has no poster, and it would otherwise be
      # typed into the poster field as if it were an address.
      attributes = attributes.except(:pic) if attributes[:pic].blank? || attributes[:pic] == 'N/A'

      blank_entry.tap { |entry| entry.assign_attributes(attributes.compact) }
    end

    def blank_entry(**attributes) = Entry.new(list: @list, **attributes)
end
