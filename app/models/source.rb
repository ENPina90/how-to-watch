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

  def imdb?   = kind == "imdb"
  def direct? = kind == "direct"

  # Build the playable embed URL for an entry (plus optional subentry for series/anime).
  # Returns nil if no template matches the entry's media type.
  def url_for(entry, subentry: nil, autoplay: false)
    build_url(entry.media, entry_variables(entry, subentry), autoplay: autoplay)
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

  def entry_variables(entry, subentry)
    {
      imdb:             entry.imdb,
      series_imdb:      entry.series_imdb.presence || entry.imdb,
      # Series/anime carry season/episode on the subentry; standalone `episode`
      # entries carry them on the entry itself.
      season:           subentry&.season.presence || entry.season,
      episode:          subentry&.episode.presence || entry.episode,
      absolute_episode: subentry&.calculate_absolute_episode_number,
      source_key:       entry.source_key,
    }
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
