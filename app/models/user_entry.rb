# frozen_string_literal: true

class UserEntry < ApplicationRecord
  belongs_to :user
  belongs_to :entry

  validates :user_id, presence: true
  validates :entry_id, presence: true
  validates :user_id, uniqueness: { scope: :entry_id }
  validates :review, inclusion: { in: 1..10 }, allow_nil: true

  scope :completed, -> { where(completed: true) }
  scope :incomplete, -> { where(completed: false) }
  scope :with_review, -> { where.not(review: nil) }
  scope :with_comment, -> { where.not(comment: [nil, '']) }
  scope :recently_completed, -> { completed.order(completed_at: :desc) }
  scope :recently_watched, -> { order(last_watched_at: :desc) }

  before_update :set_completed_at, if: :completed_changed?
  before_update :set_last_watched_at, if: :will_save_change_to_completed?
  after_update :advance_user_list_position, if: :saved_change_to_completed?

  # Mark as completed
  def mark_completed!
    update!(completed: true, completed_at: Time.current, last_watched_at: Time.current)
  end

  # Mark as incomplete
  def mark_incomplete!
    update!(completed: false, completed_at: nil)
  end

  # Toggle completion status
  def toggle_completed!
    if completed?
      mark_incomplete!
    else
      mark_completed!
    end
  end

  # Set rating (1-10)
  def set_review!(rating)
    update!(review: rating.clamp(1, 10))
  end

  # Add or update comment
  def set_comment!(text)
    update!(comment: text)
  end

  # Check if user has reviewed this entry
  def reviewed?
    review.present?
  end

  # Check if user has commented on this entry
  def commented?
    comment.present?
  end

  private

  def set_completed_at
    if completed?
      self.completed_at = Time.current
    else
      self.completed_at = nil
    end
  end

  def set_last_watched_at
    self.last_watched_at = Time.current if completed?
  end

  # Advance user's position in the list when they complete an entry
  def advance_user_list_position
    # Only advance if the user just completed the entry (not if they marked it incomplete)
    if completed?
      entry.list.advance_user_position!(user)
    end
  end
end
