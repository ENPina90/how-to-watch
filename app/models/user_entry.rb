# frozen_string_literal: true

class UserEntry < ApplicationRecord
  belongs_to :user
  belongs_to :entry

  validates :user_id, presence: true
  validates :entry_id, presence: true
  validates :user_id, uniqueness: { scope: :entry_id }
  validates :review, inclusion: { in: 1..10 }, allow_nil: true

  # How far through a film counts as having watched it. The last stretch is credits, and
  # a viewer who stops there has seen the film -- waiting for the player's own `completed`
  # would leave it unticked for everybody who does not sit through them.
  COMPLETION_FRACTION = 0.95

  scope :completed, -> { where(completed: true) }
  scope :incomplete, -> { where(completed: false) }
  scope :with_review, -> { where.not(review: nil) }
  scope :with_comment, -> { where.not(comment: [nil, '']) }
  scope :recently_completed, -> { completed.order(completed_at: :desc) }
  scope :recently_watched, -> { order(last_watched_at: :desc) }

  before_update :set_completed_at, if: :completed_changed?
  before_update :set_last_watched_at, if: :will_save_change_to_completed?
  # Temporarily disabled auto-advance callback
  # after_update :advance_user_list_position, if: :saved_change_to_completed?

  # Mark as completed
  def mark_completed!
    update!(completed: true, completed_at: Time.current, last_watched_at: Time.current)
  end

  # --- Player position ------------------------------------------------------------------
  #
  # Only providers whose player talks to the page around it report any of this (vidsrc, in
  # practice -- see docs/guides/VIDSRC.md §6). On everything else these stay nil and the
  # entry behaves as it always did.

  # Records where the player has reached, and ticks the entry off once it is far enough
  # through. `finished` is the player saying the video ended; the fraction is the fallback
  # for the far more common case of somebody stopping during the credits.
  #
  # Completion is only ever switched on here. Somebody who un-ticks a film they have seen
  # and then scrubs through it should not have that undone by the player.
  def record_progress!(seconds, duration: nil, finished: false)
    seconds = [seconds.to_f, 0.0].max

    changes = { player_progress: seconds }
    # `completed` going true fires set_completed_at and set_last_watched_at, which stamp
    # the present -- right here, because this is somebody watching it now.
    changes[:completed] = true if !completed? && watched_enough?(seconds, duration, finished)

    update!(changes)
  end

  # Where the player should pick up, or nil to start from the beginning.
  #
  # A film watched to the end reports back a position in its own credits, and resuming
  # there means pressing play and watching it finish. Past the completion mark it starts
  # again; a viewer who then stops halfway through the rewatch resumes there as normal.
  def resume_position
    return nil unless player_progress.to_f.positive?

    mark = completion_mark
    return nil if mark && player_progress >= mark

    player_progress
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

  def watched_enough?(seconds, duration, finished)
    return true if finished

    mark = completion_mark(duration)
    mark.present? && seconds >= mark
  end

  # The position past which the film counts as watched, or nil when nothing here knows how
  # long it is. The catalogue's runtime is preferred over the player's reported duration:
  # it is the length of the film, while the player is timing whatever file it was handed,
  # ads and all.
  def completion_mark(duration = nil)
    minutes = entry.length.to_i
    return minutes * 60 * COMPLETION_FRACTION if minutes.positive?

    duration.to_f.positive? ? duration.to_f * COMPLETION_FRACTION : nil
  end

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
      list = entry.list

      if list.ordered?
        # For ordered lists, always advance to next incomplete/untracked entry
        user_position = list.position_for_user(user)
        next_entry = list.find_next_incomplete_entry_for_user(user, entry.position)

        if next_entry
          user_position.update!(current_position: next_entry.position)
        end
        # If no next incomplete entry, position stays at current completed entry
      else
        # For unordered lists, use the existing advance logic (random)
        list.advance_user_position!(user)
      end
    end
  end
end
