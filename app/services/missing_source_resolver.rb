# frozen_string_literal: true

# Works out how an entry that cannot resolve through a Source template *should* be wired,
# so the legacy `source` columns can eventually be dropped (plan item #20c).
#
# Tries the cheapest, most certain answer first and only guesses at the very end:
#
#   :imdb_in_url    the legacy URL already contains a tt id  -> use it (verified via OMDB)
#   :imdb_from_tmdb the entry has a tmdb id                  -> ask TMDB for the imdb id
#   :direct_source  the URL points at Drive/mega/etc.        -> direct provider + source_key
#   :title_search   nothing else worked                      -> OMDB/TMDB search, SUGGESTION ONLY
#   :none           no legacy URL to work from
#
# The ordering matters for correctness, not just speed. Most of the unresolved entries are
# fan edits ("Episode IV - A New Hope: Revisited") and anime specials hosted on Drive or
# mega. A title search matches those to the *official* film with high confidence, and
# applying that would silently swap someone's fan edit for the studio release. Anything
# with a direct-hosting URL is therefore classified as :direct_source and never searched.
class MissingSourceResolver
  IMDB_ID = /\b(tt\d{6,})\b/

  # Legacy URL -> [provider slug, source_key]. Mirrors the original sources:backfill task.
  DIRECT_PATTERNS = [
    [%r{drive\.google\.com/(?:file/d/|embed/d/)([^/?]+)}i, 'google-drive'],
    [%r{mega\.nz/embed/(.+)\z}i,                           'mega'],
    [%r{youtube\.com/embed/(.+)\z}i,                       'youtube'],
    [%r{archive\.org/embed/(.+)\z}i,                       'archive-org']
  ].freeze

  def initialize(entry, tmdb: TmdbService.new)
    @entry = entry
    @tmdb = tmdb
  end

  def call
    return proposal(:none, note: 'no legacy source URL to work from') if legacy_url.blank?

    imdb_in_url || imdb_from_tmdb || direct_source || title_search
  end

  private

  def legacy_url
    @legacy_url ||= @entry.source.presence || @entry.source_two.presence
  end

  # --- tier 1: the id is sitting in the URL --------------------------------------------
  def imdb_in_url
    id = legacy_url[IMDB_ID, 1]
    return nil if id.blank?

    record = OmdbApi.get_movie(id)
    proposal(:imdb_in_url, imdb: id, confidence: :exact,
             note: record ? "OMDB says #{record['Title']} (#{record['Year']})" : 'OMDB could not confirm the id')
  end

  # --- tier 2: we already know the TMDB id ---------------------------------------------
  def imdb_from_tmdb
    return nil if @entry.tmdb.blank?

    type = %w[series anime].include?(@entry.media) ? 'show' : 'movie'
    id = @tmdb.fetch_imdb_id(@entry.tmdb, type)
    return nil if id.blank?

    proposal(:imdb_from_tmdb, imdb: id, confidence: :exact, note: "from TMDB id #{@entry.tmdb}")
  end

  # --- tier 3: it is hosted somewhere specific, so keep pointing at that ----------------
  def direct_source
    slug, key = classify_direct(legacy_url)
    return nil if slug.nil?

    provider = Source.find_by(slug: slug)
    return proposal(:direct_source, confidence: :review, note: "no Source row with slug #{slug}") if provider.nil?

    proposal(:direct_source, provider: provider, source_key: key, confidence: :exact,
             note: "hosted on #{slug}")
  end

  def classify_direct(url)
    DIRECT_PATTERNS.each do |pattern, slug|
      match = url.match(pattern)
      return [slug, match[1]] if match
    end

    # Anything else that is not one of the imdb-keyed providers is passed through whole
    # by the catch-all "custom" provider.
    return ['custom', url] unless url.match?(/vidsrc/i)

    nil
  end

  # --- tier 4: guess from the title, for a human to confirm ----------------------------
  def title_search
    candidates = search_candidates
    return proposal(:title_search, confidence: :review, note: 'no candidates found') if candidates.empty?

    best = candidates.first
    proposal(:title_search, imdb: best[:imdb], confidence: :review, candidates: candidates,
             note: "best guess #{best[:title]} (#{best[:year]}) from #{best[:via]}")
  end

  def search_candidates
    (omdb_candidates + tmdb_candidates).uniq { |c| c[:imdb] }.first(3)
  end

  def omdb_candidates
    ids = OmdbApi.search_by_title(@entry.name.to_s, number: 3, year: @entry.year) || []
    ids.filter_map do |id|
      record = OmdbApi.get_movie(id)
      next if record.nil?

      { imdb: id, title: record['Title'], year: record['Year'], via: 'OMDB' }
    end
  rescue StandardError => e
    Rails.logger.warn "OMDB search failed for #{@entry.name}: #{e.message}"
    []
  end

  def tmdb_candidates
    results = if %w[series anime].include?(@entry.media)
                @tmdb.search_tv(@entry.name.to_s, year: @entry.year)['results']
              else
                @tmdb.search_movie(@entry.name.to_s, year: @entry.year)['results']
              end

    (results || []).first(2).filter_map do |result|
      type = %w[series anime].include?(@entry.media) ? 'show' : 'movie'
      id = @tmdb.fetch_imdb_id(result['id'], type)
      next if id.blank?

      { imdb: id, title: result['title'] || result['name'],
        year: (result['release_date'] || result['first_air_date']).to_s[0, 4], via: 'TMDB' }
    end
  rescue TmdbService::RequestError => e
    Rails.logger.warn "TMDB search failed for #{@entry.name}: #{e.message}"
    []
  end

  def proposal(strategy, imdb: nil, provider: nil, source_key: nil, confidence: :review, note: nil, candidates: [])
    { entry: @entry, strategy: strategy, imdb: imdb, provider: provider, source_key: source_key,
      confidence: confidence, note: note, candidates: candidates }
  end
end
