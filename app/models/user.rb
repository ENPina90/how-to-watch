class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  has_many :lists
  has_many :list_user_entries
  has_many :user_entries, dependent: :destroy
  has_many :watched_entries, -> { where(user_entries: { completed: true }) }, through: :user_entries, source: :entry
  has_many :unwatched_entries, -> { where(user_entries: { completed: false }) }, through: :user_entries, source: :entry
  has_many :reviewed_entries, -> { where.not(user_entries: { review: nil }) }, through: :user_entries, source: :entry

  # Get or create user_entry record for a specific entry
  def user_entry_for(entry)
    user_entries.find_or_create_by(entry: entry)
  end

  # Check if user has completed an entry
  def completed?(entry)
    user_entry_for(entry).completed?
  end

  # Mark entry as completed for this user
  def mark_completed!(entry)
    user_entry_for(entry).mark_completed!
  end

  # Mark entry as incomplete for this user
  def mark_incomplete!(entry)
    user_entry_for(entry).mark_incomplete!
  end

  # Toggle completion status for an entry
  def toggle_completed!(entry)
    user_entry_for(entry).toggle_completed!
  end

  # Add review for an entry
  def review_entry!(entry, rating)
    user_entry_for(entry).set_review!(rating)
  end

  # Add comment for an entry
  def comment_on_entry!(entry, comment)
    user_entry_for(entry).set_comment!(comment)
  end

  # Get user's review for an entry
  def review_for(entry)
    user_entry_for(entry).review
  end

  # Get user's comment for an entry
  def comment_for(entry)
    user_entry_for(entry).comment
  end

  # Remove user's tracking for an entry (delete UserEntry record)
  def remove_tracking_for!(entry)
    user_entries.where(entry: entry).destroy_all
  end

  # Letterboxd integration methods
  def letterboxd_connected?
    letterboxd_access_token.present? && letterboxd_token_valid?
  end

  def letterboxd_token_valid?
    return false unless letterboxd_token_expires_at
    letterboxd_token_expires_at > Time.current
  end

  def letterboxd_token_needs_refresh?
    return true unless letterboxd_token_expires_at
    letterboxd_token_expires_at <= 1.hour.from_now
  end

  def refresh_letterboxd_token!
    return false unless letterboxd_refresh_token.present?

    service = LetterboxdService.new
    response = service.refresh_token(letterboxd_refresh_token)

    if response && response['access_token']
      update!(
        letterboxd_access_token: response['access_token'],
        letterboxd_refresh_token: response['refresh_token'] || letterboxd_refresh_token,
        letterboxd_token_expires_at: Time.current + response['expires_in'].seconds
      )
      true
    else
      Rails.logger.error("Failed to refresh Letterboxd token for user #{id}")
      false
    end
  end

  def valid_letterboxd_token
    return nil unless letterboxd_connected?

    if letterboxd_token_needs_refresh?
      return letterboxd_access_token if refresh_letterboxd_token!
      return nil
    end

    letterboxd_access_token
  end

  def sync_entry_to_letterboxd!(entry)
    return { error: true, message: "Not connected to Letterboxd" } unless letterboxd_connected?

    user_entry = user_entry_for(entry)
    return { error: true, message: "Entry not completed" } unless user_entry.completed?

    token = valid_letterboxd_token
    return { error: true, message: "Invalid Letterboxd token" } unless token

    service = LetterboxdService.new
    service.sync_user_entry_to_letterboxd(user_entry, token)
  end

  def disconnect_letterboxd!
    update!(
      letterboxd_access_token: nil,
      letterboxd_refresh_token: nil,
      letterboxd_token_expires_at: nil,
      letterboxd_user_id: nil,
      letterboxd_username: nil
    )
  end
end
