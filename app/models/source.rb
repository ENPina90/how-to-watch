# frozen_string_literal: true

# A streaming provider definition. Owns the URL *template(s)*; the variable data
# (imdb id, season/episode, or an opaque source_key) lives on the Entry/Subentry.
# The playable embed URL is computed on demand via #url_for, so swapping a dead
# provider's URL pattern is a one-row update instead of a backfill across entries.
class Source < ApplicationRecord
  KINDS = %w[imdb direct].freeze

  has_many :lists,   foreign_key: :provider_id, dependent: :nullify
  has_many :entries, foreign_key: :provider_id, dependent: :nullify
  has_many :notifications, as: :subject, dependent: :destroy

  before_validation :set_slug_from_name

  # Warnings are derived from `valid_until` and `active`, so they have to be recomputed the
  # moment either moves -- renewing a provider should clear its warning there and then, not
  # at the next nightly scan. after_commit because the notifier writes rows of its own.
  after_commit :refresh_expiry_notifications, on: %i[create update],
                                              if: -> { saved_change_to_valid_until? || saved_change_to_active? }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(active: true) }

  # --- Expiry ---------------------------------------------------------------------------
  #
  # `valid_until` is when the provider's address should be checked again, not a promise it
  # works until then. Ours is a domain registration that has to be renewed; vidsrc's are
  # theirs to rotate whenever they like. Null means "cannot lapse" -- Drive, YouTube and the
  # rest -- and those never warn, so the warnings that do appear are worth reading.

  # How long before the date a warning starts. A month is enough to renew a domain without
  # rushing, and short enough that the page is not permanently amber.
  EXPIRY_WARNING_WINDOW = 30.days

  # What a renewal adds. Matches how domains are actually sold.
  RENEWAL_PERIOD = 1.year

  scope :perishable, -> { where.not(valid_until: nil) }
  scope :expiring_by, ->(date) { perishable.where(valid_until: ..date) }
  scope :by_expiry, -> { order(Arel.sql('valid_until ASC NULLS LAST')) }

  # Writes the order shown on /sources back as positions 1..N.
  #
  # Takes the whole order rather than one moved row: positions here have collided in the
  # past -- the seed and the admin UI both wrote them independently -- and renumbering the
  # lot on every drop is what quietly repairs that. Position is not decoration either;
  # Entry#resolved_source falls back to the first active imdb provider by position, so the
  # top of this list is what a channel plays through when its own provider is gone.
  def self.reorder!(ids)
    ordered = ids.map(&:to_i).uniq
    found = where(id: ordered).pluck(:id).to_set

    transaction do
      ordered.each_with_index do |id, index|
        next unless found.include?(id)

        where(id: id).update_all(position: index + 1, updated_at: Time.current)
      end
    end
  end

  def perishable? = valid_until.present?
  def expired?      = perishable? && valid_until < Date.current
  def expiring_soon? = perishable? && !expired? && valid_until <= EXPIRY_WARNING_WINDOW.from_now.to_date

  # :fine / :soon / :expired, or nil for a provider that cannot lapse. One value for the
  # view to switch on rather than three predicates it has to combine correctly.
  def expiry_state
    return nil unless perishable?
    return :expired if expired?

    expiring_soon? ? :soon : :fine
  end

  # Negative once it is past, which is what lets one sentence describe both sides.
  def days_until_expiry = perishable? ? (valid_until - Date.current).to_i : nil

  # Extends from the existing date rather than from today, so renewing early does not throw
  # away the time already paid for. From today when it has already lapsed.
  def renew!(period = RENEWAL_PERIOD)
    from = perishable? && valid_until > Date.current ? valid_until : Date.current
    update!(valid_until: from + period)
  end

  # --- Testing a provider ------------------------------------------------------------

  # A film to probe an imdb provider with. Widely available, and vidsrc's own docs use it,
  # so a provider that cannot serve this is broken rather than merely missing something
  # obscure.
  PROBE_IMDB = 'tt1300854'
  PROBE_TITLE = 'Iron Man 3'

  # A URL that plays something through this provider, for the test page.
  #
  # An imdb provider is probed with a known film. A direct one cannot be: its templates take
  # a source_key that belongs to a particular file, so the only honest test is something
  # already filed under it -- and if nothing is, there is nothing to test.
  # autoplay is on: "does it play" is the question, and on a custom domain autoplay is
  # itself part of what is being tested -- that is the whole reason for having one.
  def probe_url
    return build_url('movie', { imdb: PROBE_IMDB }, autoplay: true) if imdb?

    entry = entries.where.not(source_key: [nil, '']).first
    entry && url_for(entry, autoplay: true)
  end

  # What the test page is actually playing, so the tab does not just show an unlabelled
  # video.
  def probe_label
    return "#{PROBE_TITLE} (#{PROBE_IMDB})" if imdb?

    entries.where.not(source_key: [nil, '']).first&.name
  end

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
    # Our CNAMEd domain: vidsrc's own backend behind our host, so the same adapter drives it.
    "framerelay"      => "vidsrc",
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

  def refresh_expiry_notifications
    SourceExpiryNotifier.call
  end
end
