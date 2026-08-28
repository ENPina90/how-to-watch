# frozen_string_literal: true

require 'csv'
require 'net/http'
require 'json'


class Entry < ApplicationRecord
  belongs_to :list
  belongs_to :provider, class_name: 'Source', optional: true
  has_one_attached :poster
  # Deleted in bulk rather than one destroy per row: a long-running series has
  # hundreds of subentries, and Subentry's per-record callbacks only exist to clear
  # references that #release_subentry_references already clears in two statements.
  has_many :subentries, dependent: :delete_all
  has_many :user_entries, dependent: :destroy
  has_many :user_entry_positions, dependent: :destroy
  has_many :users_who_watched, -> { where(user_entries: { completed: true }) }, through: :user_entries, source: :user
  has_many :users_who_reviewed, -> { where.not(user_entries: { review: nil }) }, through: :user_entries, source: :user
  # No dependent: :destroy here -- `current` is always one of this entry's own
  # subentries, so the has_many above already removes it. Destroying it a second
  # time (after the bulk delete) would just re-run callbacks against a dead row.
  belongs_to :current, class_name: 'Subentry', optional: true
  validates :name, presence: true, uniqueness: { scope: [:list, :series] }
  validates :media, presence: true

  accepts_nested_attributes_for :subentries, allow_destroy: true

  include PgSearch::Model
  pg_search_scope :search_by_input,
                  against: %i[name franchise category writer actors genre director],
                  using:   {
                    tsearch: {
                      prefix: true,
                    },
                  }

  # A series, a season of one, and an episode of one are all filed under the show they
  # belong to. `anime` is the same shape as `series`; a season is a `series` row whose name
  # carries the season number.
  SERIES_MEDIA = %w[series anime].freeze
  SHOW_MEDIA = %w[series anime episode].freeze

  # `media` is free text in the entry form, so it can arrive as "Movie". Every
  # comparison against it -- the provider template lookup, the partial picker, the
  # legacy URL builder -- is case-sensitive, so normalize on the way in.
  before_validation :normalize_media

  # A show is its own series, and the OMDB import only fills `series` for episodes -- so a
  # series row arrives with the show's title in `name` and nothing in `series`. Filling it
  # in makes the two agree, and gives the category below something to read.
  before_validation :name_after_own_series, on: :create, if: -> { SERIES_MEDIA.include?(media) }

  # Everything under a show is categorised by that show, unless it was given a category of
  # its own. On create only: a category cleared by hand later is a decision, not a gap.
  before_validation :categorise_under_show, on: :create, if: -> { SHOW_MEDIA.include?(media) }

  # A pasted direct URL (Drive share link, mega link, YouTube, archive.org, or anything
  # else). It is not a column: it gets classified into provider + source_key so playback
  # goes through the same template machinery as everything else.
  attr_accessor :source_url

  before_validation :apply_source_url, if: -> { source_url.present? }

  # Runs ahead of every dependent-destroy callback (prepend), so the FKs pointing
  # into this entry's subentries are gone before the bulk delete fires. Scoped by
  # subentry id rather than entry id so a stray cross-entry reference can't survive.
  before_destroy :release_subentry_references, prepend: true

  # Both of these hit the network, so they run after the transaction commits and
  # off the request thread -- otherwise a slow or dead host holds the connection
  # and the new row's locks open for the duration of the request.
  # Unconditional now: the URL to check is computed, so there is no legacy column to
  # gate on. The job no-ops when nothing resolves.
  after_commit :enqueue_source_check, on: :create
  # One registration covering both create and update: two after_commit callbacks
  # naming the same method would dedupe, and only the last one would survive.
  after_commit :attach_poster_from_pic, on: %i[create update], if: -> { saved_change_to_pic? && should_attach_poster? }

  def self.create_from_source(entry, list, seen)
    entry = OmdbApi.normalize_omdb_data(entry) unless entry[:seed]
    Entry.create!(
      position:     entry[:position] || next_position(list),
      franchise:    entry[:franchise],
      media:        entry[:media],
      season:       entry[:season],
      episode:      entry[:episode],
      completed:    seen,
      name:         entry[:name],
      tmdb:         entry[:tmdb],
      imdb:         entry[:imdb],
      series_imdb:  entry[:series_imdb],
      trailer:      entry[:trailer],
      series:       entry[:series],
      category:     entry[:series],
      length:       entry[:length],
      year:         entry[:year],
      plot:         entry[:plot],
      pic:          entry[:pic],
      genre:        entry[:genre],
      director:     entry[:director],
      writer:       entry[:writer],
      actors:       entry[:actors],
      rating:       entry[:rating],
      language:     entry[:language],
      note:         entry[:note],
      list:         list,
    )
  rescue StandardError => e
    handle_creation_error(entry, e)
  end

  def self.next_position(list)
    list.entries.empty? ? 1 : list.entries.maximum(:position) + 1
  end

  def self.handle_creation_error(entry, error)
    FailedEntry.create(name: entry[:name] || entry['Title'], year: entry[:year] || entry['Year'])
    message = "Failed to create movie entry: #{error.message}"
    Rails.logger.error(message)
    message
  end

  def self.to_csv
    CsvExporterService.generate_seed_csv
  end

  def self.like(name)
    where('name ILIKE ?', "%#{name}%").first
  end

  # Checks the URL the player will actually load, rather than the legacy `source` column
  # that new entries no longer write.
  def check_source
    url = embed_url
    update(stream: url.present? && UrlCheckerService.new(url).valid_source?)
  end

  def release_subentry_references
    subentry_ids = subentries.select(:id)
    UserEntryPosition.where(current_subentry_id: subentry_ids).update_all(current_subentry_id: nil)
    Entry.where(current_id: subentry_ids).update_all(current_id: nil)
  end

  # Which section this entry falls in under a given grouping -- the same question
  # ListsController#filter_entries answers for a whole channel at once, asked about one
  # entry so a card added without a reload can be put where it belongs. Genre is a list, so
  # an entry can be in several sections at once; a grouping that reads an attribute has
  # exactly one, and 'Other' stands in for a blank, as it does on the page.
  def section_keys(criteria, user: nil)
    case criteria
    when 'Position' then []
    when 'Genre' then genre.to_s.split(',').map(&:strip).reject(&:empty?).presence || ['Other']
    when 'Year' then year.present? ? ["#{(year / 10) * 10}s"] : []
    when 'Watched' then [completed_by?(user) ? 'Watched' : 'Unwatched']
    else [public_send(criteria.downcase).presence || 'Other']
    end
  end

  # The show this entry belongs to. A series or a season carries it in `series` once the
  # callback above has run, and falls back to its own name; an episode always has it.
  def show_name
    return series.presence || name if SERIES_MEDIA.include?(media)

    series
  end

  def name_after_own_series
    self.series = name if series.blank?
  end

  def categorise_under_show
    self.category = show_name if category.blank?
  end

  def normalize_media
    self.media = media.to_s.strip.downcase.presence
  end

  def apply_source_url
    provider, key = Source.for_url(source_url.strip)

    if provider.nil?
      errors.add(:source_url, 'is not a URL we recognise, and no provider is configured for it')
      return
    end

    self.provider = provider
    self.source_key = key
  end

  # The direct URL this entry currently plays from, for pre-filling the edit form.
  def current_source_url
    return nil unless provider&.direct?

    embed_url
  end

  def enqueue_source_check
    CheckEntrySourceJob.perform_later(self)
  rescue StandardError => e
    Rails.logger.error "Failed to enqueue source check for Entry #{id}: #{e.message}"
  end

  # The Source provider to use for this entry: its own override, else the list default.
  # If that provider is missing or has been deactivated, fall back to a present, active
  # source so the entry always loads a working player on first view.
  def resolved_source
    linked = provider || list&.provider
    return linked if linked&.active?

    # imdb entries can play on any active imdb provider; direct entries only work on
    # their own linked provider (its source_key is provider-specific), so keep it.
    return Source.active.where(kind: 'imdb').order(:position).first if imdb.present?

    linked
  end

  # Providers this entry can actually play on:
  #   - every active imdb provider, when the entry has an imdb id, and
  #   - its own direct provider, when a source_key is present (the key is provider-specific).
  def eligible_sources
    sources = []
    sources.concat(Source.active.where(kind: 'imdb').order(:position).to_a) if imdb.present?
    current = resolved_source
    sources << current if current&.direct? && source_key.present?
    sources.uniq
  end

  # Computed, on-demand embed URL built from the resolved provider's template.
  # Pass the current subentry for series/anime so season/episode resolve correctly.
  # Blank means nothing can play it -- callers show "no source available" rather than
  # loading an iframe that cannot work.
  def embed_url(subentry: nil, autoplay: false)
    resolved_source&.url_for(self, subentry: subentry, autoplay: autoplay).presence
  end

  # Get user's current episode for this entry
  def current_subentry_for_user(user)
    return nil unless user
    return current unless media == 'series' || media == 'anime' # Fallback to entry-level current

    user_position = UserEntryPosition.find_or_create_for(user, self)
    user_position.current_subentry || current # Fallback to entry-level current
  end

  # Update user's episode position
  def update_user_subentry!(user, subentry)
    return unless user && subentry

    user_position = UserEntryPosition.find_or_create_for(user, self)
    user_position.update_to_subentry!(subentry)
  end

  def next
    list.entries.where('position > ?', position).order(:position).first
  end

  def previous
    list.entries.where('position < ?', position).order(:position).last
  end

  # READ. Returns nil when the user has never touched this entry.
  #
  # This is called while rendering -- `entries/_completion_status` runs once per entry on
  # every list page -- so it must not write. It used to be find_or_create_by, which meant
  # simply *looking* at a list inserted a user_entries row for every entry on the page.
  # Use #user_entry_for! on the paths that actually record something.
  def user_entry_for(user)
    return nil unless user

    # Use the preloaded association when the caller has eager-loaded it (see the
    # `includes(:user_entries)` in ListsController), otherwise fall back to a lookup.
    if user_entries.loaded?
      user_entries.detect { |user_entry| user_entry.user_id == user.id }
    else
      user_entries.find_by(user: user)
    end
  end

  # WRITE. Creates the tracking row if it does not exist yet.
  def user_entry_for!(user)
    user_entries.find_or_create_by(user: user)
  end

  # Check if a specific user has completed this entry
  def completed_by?(user)
    return completed if user.nil? # Fallback to old system
    user_entry_for(user)&.completed? || false
  end

  # Mark as completed for a specific user
  def mark_completed_by!(user)
    user_entry_for!(user).mark_completed!
    self.list.watched!(user) if user == self.list.user # Update list current if it's the list owner
  end

  # Mark as incomplete for a specific user
  def mark_incomplete_by!(user)
    # No row means nothing has been recorded, which already reads as incomplete.
    user_entry_for(user)&.mark_incomplete!
  end

  # Toggle completion for a specific user
  def toggle_completed_by!(user)
    user_entry = user_entry_for!(user)
    user_entry.toggle_completed!
    self.list.watched!(user) if user == self.list.user && user_entry.completed? # Update list current if it's the list owner
    user_entry.completed?
  end

  # Get average review rating
  def average_review
    reviews = scored_reviews
    return nil if reviews.empty?
    reviews.sum.to_f / reviews.size
  end

  # Get review count
  def review_count
    scored_reviews.size
  end

  # Both aggregates render once per entry on a list page, so use the preloaded rows when
  # the caller eager-loaded them instead of two queries per entry.
  def scored_reviews
    if user_entries.loaded?
      user_entries.filter_map(&:review)
    else
      user_entries.where.not(review: nil).pluck(:review)
    end
  end

  # Get completion percentage
  def completion_percentage
    total_users = user_entries.count
    return 0 if total_users == 0
    completed_users = user_entries.where(completed: true).count
    (completed_users.to_f / total_users * 100).round(1)
  end

  # Remove user's tracking for this entry
  def remove_user_tracking!(user)
    user_entries.where(user: user).destroy_all
  end

  def streamable
    return if stream

    errors.add(:source, 'is unavailable, do you have an alternative?')
  end

  # Check if the entry's image URL is valid
  def image_valid?
    return false if pic.blank?
    TmdbService.new.validate_image_url(pic)
  end

  # Repair the entry's image if it's broken
  def repair_image!
    ImageRepairService.new.repair_entry_image(self)
  end

  # Migrate the entry's pic URL to Active Storage poster
  def migrate_poster!
    PosterMigrationService.new.migrate_entry_poster(self)
  end

  private

  # Check if we should attach a poster from pic URL
  def should_attach_poster?
    pic.present? && !poster.attached?
  end

  # Automatically attach poster from pic URL. The download and the Cloudinary
  # upload together take a couple of seconds, so they always go to a job.
  def attach_poster_from_pic
    return unless should_attach_poster?

    AttachPosterFromPicJob.perform_later(self)
  rescue StandardError => e
    # Log error but don't fail the main operation
    Rails.logger.error "Failed to enqueue poster attachment for Entry #{id}: #{e.message}"
  end
end
