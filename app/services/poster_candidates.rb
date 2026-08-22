# frozen_string_literal: true

# Gathers poster options to offer in the poster picker: TMDB's primary poster and a few
# alternates, anything reachable via the entry's imdb ids, OMDB's poster, and the posters
# already attached to the two entries above this one in the list (handy for keeping a
# series looking consistent).
#
# Extracted from EntriesController#fetch_posters. Every source is best-effort: a failure
# in one must not lose the others, which is why each is wrapped individually.
#
# Returns an array of { url:, source: } hashes, de-duplicated by url, best first.
class PosterCandidates
  RECENT_ENTRY_COUNT = 2
  TMDB_ALTERNATE_COUNT = 4

  def initialize(entry, tmdb: TmdbService.new, url_builder: nil)
    @entry = entry
    @tmdb = tmdb
    # Attached posters need a host to build an absolute URL; the controller passes a
    # lambda so this class stays free of request state.
    @url_builder = url_builder
  end

  def call
    candidates = []
    candidates.concat(tmdb_posters)
    candidates.concat(posters_via_imdb_ids)
    candidates.concat(omdb_posters)
    candidates.concat(recent_list_posters)
    candidates.uniq { |candidate| candidate[:url] }
  end

  private

  def media_type
    @media_type ||= %w[series anime episode].include?(@entry.media) ? 'tv' : 'movie'
  end

  def imdb_ids
    [@entry.imdb, @entry.series_imdb].compact_blank.uniq
  end

  def tmdb_posters
    return [] if @entry.tmdb.blank?

    posters = []
    primary = @tmdb.fetch_poster_url(@entry.tmdb, media_type)
    posters << { url: primary, source: 'TMDB' } if primary

    begin
      images = @tmdb.fetch_images(@entry.tmdb, media_type)
      (images['posters'] || []).first(TMDB_ALTERNATE_COUNT).each do |poster|
        url = TmdbService.image_url(poster['file_path'])
        posters << { url: url, source: 'TMDB' } if url
      end
    rescue TmdbService::RequestError => e
      Rails.logger.error "Error fetching TMDB images: #{e.message}"
    end

    posters
  end

  # TMDB's /find endpoint sometimes has art for a title whose tmdb id we never stored.
  def posters_via_imdb_ids
    imdb_ids.flat_map do |imdb_id|
      found = @tmdb.find_by_imdb_id(imdb_id)
      %w[movie_results tv_results].filter_map do |key|
        url = TmdbService.image_url(found[key]&.first&.dig('poster_path'))
        { url: url, source: 'TMDB (via IMDB)' } if url
      end
    rescue TmdbService::RequestError => e
      Rails.logger.error "Error fetching TMDB via IMDB id #{imdb_id}: #{e.message}"
      []
    end
  end

  def omdb_posters
    imdb_ids.filter_map do |imdb_id|
      url = @tmdb.fetch_omdb_poster_url(imdb_id)
      { url: url, source: 'OMDB' } if url
    end
  end

  def recent_list_posters
    return [] if @entry.list.blank? || @entry.position.blank?

    @entry.list.entries
          .where('position < ?', @entry.position)
          .order(position: :desc)
          .limit(RECENT_ENTRY_COUNT)
          .filter_map do |previous|
      next unless previous.poster.attached?

      url = attached_poster_url(previous)
      { url: url, source: "Recent: #{previous.name}" } if url
    end
  end

  def attached_poster_url(entry)
    if entry.poster.service_name == 'cloudinary'
      entry.poster.url
    else
      @url_builder&.call(entry.poster)
    end
  rescue StandardError => e
    Rails.logger.error "Error fetching poster for entry #{entry.id}: #{e.message}"
    nil
  end
end
