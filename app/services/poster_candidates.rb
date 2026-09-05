# frozen_string_literal: true

# Gathers poster options to offer in the poster picker.
#
# Two kinds of source. The id-based ones -- TMDB by tmdb id, TMDB via imdb id, OMDB by imdb
# id -- are exact but only answer for entries whose ids were stored and are right. The
# name-based ones search for the title, which is what covers everything else: a third of
# the entries with a broken poster carry no id at all, and an episode's id resolves to the
# show, so the picker used to offer the same series poster for all 1,595 of them.
#
# Ordered most-trustworthy first: the exact art for this episode, then art keyed by id,
# then title searches, then posters borrowed from neighbouring entries, then the open web.
# Search results are labelled with the title and year they matched, because a title search
# can quietly land on a different film of the same name and you should be able to see that
# before you pick it.
#
# Extracted from EntriesController#fetch_posters. Every source is best-effort: a failure in
# one must not lose the others, which is why each is wrapped individually.
#
# Returns an array of { url:, source: } hashes, de-duplicated by url, best first.
class PosterCandidates
  RECENT_ENTRY_COUNT = 2
  TMDB_ALTERNATE_COUNT = 4
  SEARCH_RESULT_COUNT = 3
  # The picker is a scrolling grid, not a catalogue. Past a couple of dozen the useful ones
  # are no easier to find than they were with four.
  MAX_CANDIDATES = 24

  def initialize(entry, tmdb: TmdbService.new, image_search: GoogleImageSearch.new, url_builder: nil)
    @entry = entry
    @tmdb = tmdb
    @image_search = image_search
    # Attached posters need a host to build an absolute URL; the controller passes a
    # lambda so this class stays free of request state.
    @url_builder = url_builder
  end

  def call
    candidates = []
    candidates.concat(episode_art)
    candidates.concat(tmdb_posters)
    candidates.concat(posters_via_imdb_ids)
    candidates.concat(omdb_posters)
    candidates.concat(tmdb_search_posters)
    candidates.concat(omdb_search_posters)
    candidates.concat(recent_list_posters)
    candidates.concat(web_image_posters)
    candidates.uniq { |candidate| candidate[:url] }.first(MAX_CANDIDATES)
  end

  private

  def media_type
    @media_type ||= %w[series anime episode].include?(@entry.media) ? 'tv' : 'movie'
  end

  def imdb_ids
    [@entry.imdb, @entry.series_imdb].compact_blank.uniq
  end

  # What to search for. An episode is looked up under the show it belongs to: its own name
  # ("The Race") is not a title anything holds art for.
  def search_title
    @search_title ||= (@entry.media == 'episode' ? @entry.series.presence : nil) || @entry.name
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

  # The art for this actual episode, rather than for the show it is in: the still, and the
  # poster for its season. Nearly every episode carries the show's name, its season and its
  # episode number, so the show's tmdb id can be searched for when it was never stored.
  def episode_art
    return [] unless @entry.media == 'episode'

    series_id = @entry.tmdb.presence || series_tmdb_id
    return [] if series_id.blank? || @entry.season.blank? || @entry.episode.blank?

    art = []

    still = TmdbService.image_url(@tmdb.fetch_episode(series_id, @entry.season, @entry.episode)['still_path'])
    art << { url: still, source: "TMDB still: S#{@entry.season}E#{@entry.episode}" } if still

    season_poster = TmdbService.image_url(@tmdb.fetch_season(series_id, @entry.season)['poster_path'])
    art << { url: season_poster, source: "TMDB: season #{@entry.season}" } if season_poster

    art
  rescue TmdbService::RequestError => e
    Rails.logger.error "Error fetching episode art for entry #{@entry.id}: #{e.message}"
    []
  end

  def series_tmdb_id
    return @series_tmdb_id if defined?(@series_tmdb_id)

    @series_tmdb_id = begin
      name = @entry.series.presence
      name && @tmdb.search_tv(name)['results']&.first&.dig('id')&.to_s
    rescue TmdbService::RequestError => e
      Rails.logger.error "Error searching TMDB for series #{@entry.series.inspect}: #{e.message}"
      nil
    end
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

  # The one source that works for an entry carrying no ids at all.
  def tmdb_search_posters
    return [] if search_title.blank?

    results = if media_type == 'tv'
                @tmdb.search_tv(search_title, year: @entry.year)['results']
              else
                @tmdb.search_movie(search_title, year: @entry.year)['results']
              end

    (results || []).filter_map do |result|
      url = TmdbService.image_url(result['poster_path'])
      title = result['title'] || result['name']
      next unless url && plausible_match?(title)

      { url: url, source: "TMDB search: #{label(title, (result['release_date'] || result['first_air_date']).to_s[0, 4])}" }
    end.first(SEARCH_RESULT_COUNT)
  rescue TmdbService::RequestError => e
    Rails.logger.error "Error searching TMDB for #{search_title.inspect}: #{e.message}"
    []
  end

  def omdb_search_posters
    return [] if search_title.blank?

    OmdbApi.search_with_posters(search_title, year: @entry.year, limit: SEARCH_RESULT_COUNT)
           .filter_map do |result|
      next unless plausible_match?(result[:title])

      { url: result[:poster], source: "OMDB search: #{label(result[:title], result[:year])}" }
    end
  rescue StandardError => e
    Rails.logger.error "Error searching OMDB for #{search_title.inspect}: #{e.message}"
    []
  end

  # Off unless the Google keys are set; see GoogleImageSearch.
  def web_image_posters
    @image_search.call(image_search_query, portrait_only: @entry.media != 'episode')
                 .map { |result| { url: result[:url], source: "Web: #{result[:host]}" } }
  end

  # "poster" earns its place in the query: without it an image search for a film's name
  # returns stills and press photos.
  def image_search_query
    if @entry.media == 'episode'
      [search_title, "s#{@entry.season}e#{@entry.episode}", @entry.name].compact_blank.join(' ')
    else
      [search_title, @entry.year, 'poster'].compact_blank.join(' ')
    end
  end

  # A title search answers with whatever it ranked first, which for an unusual title is
  # regularly something that merely shares a word with it: "DUNE: The Definitive History of
  # the Franchise" for "The Franchise", "Rocky Legends" for "Legends". In the picker those
  # look every bit as authoritative as the right answer, and a confidently wrong poster is
  # worse than no suggestion, so a result has to actually lead with the title asked for.
  # Case and punctuation are ignored -- TMDB and OMDB disagree about both.
  def plausible_match?(title)
    query = normalise(search_title)
    candidate = normalise(title)

    return false if query.blank? || candidate.blank?

    candidate == query || candidate.start_with?("#{query} ")
  end

  def normalise(text)
    text.to_s.downcase.gsub(/[^a-z0-9]+/, ' ').strip
  end

  def label(title, year)
    year.present? ? "#{title} (#{year})" : title.to_s
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
