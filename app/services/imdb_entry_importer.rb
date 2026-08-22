# frozen_string_literal: true

# Adds a single movie/series entry to a list from an IMDb id, using OMDB for the metadata.
#
# Extracted from ListsController#add_to_list and #add_to_favorites, which were the same
# twenty lines twice. Authorization stays in the controller; this only creates.
#
# Returns { status:, entry:, message: } where status is:
#   :created   — the entry was inserted
#   :not_found — OMDB has nothing usable for that id
#   :failed    — creation failed (Entry.create_from_source returns a message, not an Entry)
class ImdbEntryImporter
  def initialize(list:, imdb_id:, tmdb_id: nil)
    @list = list
    @imdb_id = imdb_id
    @tmdb_id = tmdb_id.presence
  end

  def call
    omdb_result = OmdbApi.get_movie(@imdb_id)
    return result(:not_found, nil, 'Movie not found') if omdb_result.nil?

    # OmdbApi.normalize_omdb_data reads the "tmdb" key. Both callers used to write
    # "tmdb_id", so the id was silently dropped and the entry landed without a tmdb --
    # which is what trailers, posters and episode imports key off later.
    omdb_result['tmdb'] = @tmdb_id if @tmdb_id

    entry = Entry.create_from_source(omdb_result, @list, false)
    return result(:failed, nil, 'Failed to create entry') unless entry.is_a?(Entry)

    result(:created, entry, "Added to #{@list.name}")
  rescue StandardError => e
    Rails.logger.error "ImdbEntryImporter failed for #{@imdb_id}: #{e.message}"
    result(:failed, nil, 'Failed to create entry')
  end

  private

  def result(status, entry, message)
    { status: status, entry: entry, message: message }
  end
end
