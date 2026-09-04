# frozen_string_literal: true

# A streaming provider definition. Owns the URL *template(s)*; the variable data
# (imdb id, season/episode, or an opaque source_key) lives on the Entry/Subentry.
# The playable embed URL is computed on demand via #url_for, so swapping a dead
# provider's URL pattern is a one-row update instead of a backfill across entries.
class Source < ApplicationRecord
  KINDS = %w[imdb direct].freeze

  has_many :lists,   foreign_key: :provider_id, dependent: :nullify
  has_many :entries, foreign_key: :provider_id, dependent: :nullify

  before_validation :set_slug_from_name

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(active: true) }

  # A pasted URL -> [provider slug, source_key]. Both the manual entry form and the
  # legacy-cleanup resolver need this, so the patterns live in one place.
  # Returns [nil, nil] for imdb-keyed provider URLs, which carry no key of their own.
  DIRECT_URL_PATTERNS = [
    [%r{drive\.google\.com/(?:file/d/|embed/d/)([^/?]+)}i, 'google-drive'],
    # Accept both the share link and the embed form; the key is everything after it.
    [%r{mega\.nz/(?:embed|file)/(.+)\z}i,                   'mega'],
    [%r{youtube\.com/embed/(.+)\z}i,                        'youtube'],
    [%r{youtu\.be/(.+)\z}i,                                 'youtube'],
    [%r{archive\.org/embed/(.+)\z}i,                        'archive-org']
  ].freeze

  def self.classify_url(url)
    return [nil, nil] if url.blank?

    DIRECT_URL_PATTERNS.each do |pattern, slug|
      match = url.match(pattern)
      return [slug, match[1]] if match
    end

    # vidsrc-style URLs are imdb-keyed: the id comes off the entry, not the URL.
    return [nil, nil] if url.match?(/vidsrc/i)

    # Anything else is passed through whole by the catch-all provider.
    ['custom', url]
  end

  # Same, but resolved to the Source row. [nil, nil] when we cannot place the URL or the
  # matching provider row does not exist.
  def self.for_url(url)
    slug, key = classify_url(url)
    return [nil, nil] if slug.nil?

    [find_by(slug: slug), key]
  end

  def imdb?   = kind == "imdb"
  def direct? = kind == "direct"

  # Providers whose embedded player can be driven from the page around it, and the module
  # name of the adapter that drives it. Both vidsrc front doors resolve to one backend --
  # same wrapper, same player.js -- so one adapter serves them; the rest of the providers
  # hand the parent page no control surface at all, and a watch party on them can only tell
  # people how far apart they are.
  SYNC_ADAPTERS = {
    "vidsrc2"         => "vidsrc",
    "vidsrc-ir"       => "vidsrc",
    "vidsrc-embed.ru" => "vidsrc",
    "vidsrcme"        => "vidsrc",
  }.freeze

  def sync_adapter = SYNC_ADAPTERS[slug]
  def syncable?    = sync_adapter.present?

  # Build the playable embed URL for an entry (plus optional subentry for series/anime).
  # Returns nil if no template matches the entry's media type.
  def url_for(entry, subentry: nil, autoplay: false)
    template = template_for(entry.media)
    return nil if template.blank?

    build_url(entry.media, entry_variables(entry, subentry, template), autoplay: autoplay)
  end

  # Build a URL from a media key + an explicit variables hash, no Entry required.
  # Used by transient pages (e.g. watch_now) that only have raw imdb/season/episode.
  #
  # Returns nil when the template needs something we do not have -- an entry with no imdb
  # id, or a series with no resolved episode. Returning nil matters: Entry#embed_url only
  # falls back to the legacy source columns when this is blank, so a half-substituted URL
  # would be served as if it worked.
  def build_url(media, vars, autoplay: false)
    template = template_for(media)
    return nil if template.blank?

    url = substitute(template, vars)
    return nil if url.nil?

    append_autoplay(url, autoplay)
  end

  def template_for(media)
    templates[media.to_s.downcase].presence || templates["default"].presence
  end

  private

  def entry_variables(entry, subentry, template)
    vars = {
      imdb:             entry.imdb,
      series_imdb:      entry.series_imdb.presence || entry.imdb,
      # Series/anime carry season/episode on the subentry; standalone `episode`
      # entries carry them on the entry itself.
      season:           subentry&.season.presence || entry.season,
      episode:          subentry&.episode.presence || entry.episode,
      source_key:       entry.source_key,
    }

    # Costs a COUNT, so only work it out when the template actually asks for it. No
    # active provider does; the deactivated vidsrc-cc anime template is the only user.
    vars[:absolute_episode] = subentry&.calculate_absolute_episode_number if template.include?('%{absolute_episode}')

    vars
  end

  # Safe, eval-free substitution: only replaces %{token} placeholders, leaves every
  # other character untouched (mega keys contain '#', drive ids are opaque, etc.).
  # Every token in a template is required, so a blank one yields nil for the whole URL
  # rather than a string with a hole in it.
  def substitute(template, vars)
    missing = false

    result = template.gsub(/%\{(\w+)\}/) do
      value = vars[Regexp.last_match(1).to_sym]
      missing = true if value.blank?
      value.to_s
    end

    missing ? nil : result
  end

  def set_slug_from_name
    self.slug = name.to_s.parameterize if slug.blank? && name.present?
  end

  def append_autoplay(url, autoplay)
    return url if autoplay_param.blank?

    separator = url.include?("?") ? "&" : "?"
    "#{url}#{separator}#{autoplay_param}=#{autoplay ? 1 : 0}"
  end
end
