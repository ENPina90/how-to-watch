# frozen_string_literal: true

require 'csv'
require 'net/http'
require 'json'


class Entry < ApplicationRecord
  belongs_to :list
  has_one_attached :poster
  has_many :subentries, dependent: :destroy
  has_many :user_entries, dependent: :destroy
  has_many :users_who_watched, -> { where(user_entries: { completed: true }) }, through: :user_entries, source: :user
  has_many :users_who_reviewed, -> { where.not(user_entries: { review: nil }) }, through: :user_entries, source: :user
  belongs_to :current, class_name: 'Subentry', optional: true, dependent: :destroy
  # has_many :current_list_users, class_name: 'ListUserEntries', foreign_key: 'current_entry_id'
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

  after_create :check_source
  after_create :attach_poster_from_pic, if: :should_attach_poster?
  after_update :attach_poster_from_pic, if: :should_attach_poster?

  def self.create_from_source(entry, list, seen)
    puts "Normalizing data"
    entry = OmdbApi.normalize_omdb_data(entry) unless entry[:seed]
    puts "Createing Entry"
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
      source:       entry[:source] || generate_source(entry) || generate_source(entry),
      source_two:   entry[:source_two],
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

  def self.generate_source(entry)
    if entry[:media] == "episode"
    "https://v2.vidsrc.me/embed/#{entry[:series_imdb]}/#{entry[:season]}-#{entry[:episode]}"
    else
    "https://v2.vidsrc.me/embed/#{entry[:imdb]}"
    end
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

  def check_source
    update(stream: UrlCheckerService.new(source).valid_source?)
  end

  def set_current(change)
    subentries = self.subentries.order(:season)
    index = subentries.index(self.current) || -1
    self.update(current: subentries[index + change])
  end

  def next
    list.entries.where('position > ?', position).order(:position).first
  end

  def previous
    list.entries.where('position < ?', position).order(:position).last
  end

  def complete(boolean)
    self.update(completed: boolean)
    self.list.watched!
    completed
  end

  # Get user_entry record for a specific user
  def user_entry_for(user)
    user_entries.find_or_create_by(user: user)
  end

  # Check if a specific user has completed this entry
  def completed_by?(user)
    return completed if user.nil? # Fallback to old system
    user_entry_for(user).completed?
  end

  # Mark as completed for a specific user
  def mark_completed_by!(user)
    user_entry_for(user).mark_completed!
    self.list.watched!(user) if user == self.list.user # Update list current if it's the list owner
  end

  # Mark as incomplete for a specific user
  def mark_incomplete_by!(user)
    user_entry_for(user).mark_incomplete!
  end

  # Toggle completion for a specific user
  def toggle_completed_by!(user)
    user_entry = user_entry_for(user)
    user_entry.toggle_completed!
    self.list.watched!(user) if user == self.list.user && user_entry.completed? # Update list current if it's the list owner
    user_entry.completed?
  end

  # Get average review rating
  def average_review
    reviews = user_entries.where.not(review: nil).pluck(:review)
    return nil if reviews.empty?
    reviews.sum.to_f / reviews.count
  end

  # Get review count
  def review_count
    user_entries.where.not(review: nil).count
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

  # Automatically attach poster from pic URL
  def attach_poster_from_pic
    return unless pic.present? && !poster.attached?

    # Option 1: Background job (recommended for production)
    if Rails.env.production?
      AttachPosterFromPicJob.perform_later(self)
    else
      # Option 2: Immediate processing (for development)
      attach_poster_immediately
    end
  rescue StandardError => e
    # Log error but don't fail the main operation
    Rails.logger.error "Failed to attach poster for Entry #{id}: #{e.message}"
  end

  # Immediately attach poster (synchronous)
  def attach_poster_immediately
    Rails.logger.info "Attaching poster from pic URL for Entry #{id}: #{name}"

    service = PosterMigrationService.new
    result = service.migrate_entry_poster(self)

    if result[:status] == 'migrated'
      Rails.logger.info "Successfully attached poster: #{result[:message]}"
    else
      Rails.logger.warn "Failed to attach poster: #{result[:message]}"
    end
  rescue StandardError => e
    Rails.logger.error "Error attaching poster immediately: #{e.message}"
  end
end
