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

  # The position past which something of this length counts as watched, or nil when there
  # is no length to judge by.
  #
  # `credits` is the channel being watched from saying its programmes end that many seconds
  # before the file does (List#skip_credits_seconds). The fraction is then taken of the
  # programme rather than of the file: the up-next card is floored at this mark and moves
  # the channel on when it runs out, and moving on does not tick anything off -- so a mark
  # left at the end of the file would be one an auto-advancing viewer never reached, and
  # every entry on the channel would stay unwatched however much of it they sat through.
  #
  # Credits that swallow the whole entry are ignored rather than trusted: a mark at or
  # before the start would call a film watched the moment it opened.
  def self.completion_mark_for(runtime_seconds, credits: nil)
    runtime_seconds = runtime_seconds.to_f
    return nil unless runtime_seconds.positive?

    ends_at = runtime_seconds - credits.to_i
    ends_at = runtime_seconds unless ends_at.positive?

    ends_at * COMPLETION_FRACTION
  end

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
  # `unattended` is a position the film reached on its own, with nobody in front of it: the
  # channel warmed in the background plays while it waits, so by the time somebody flips to
  # it, it may already be past the point that counts as watched. Where it got to is still
  # worth recording -- that is where they are about to be -- but it cannot be the reason
  # the entry is called seen. Nobody saw it.
  #
  # Completion is only ever switched on here. Somebody who un-ticks a film they have seen
  # and then scrubs through it should not have that undone by the player.
  #
  # `credits` is the watching channel's skip -- see .completion_mark_for.
  def record_progress!(seconds, duration: nil, finished: false, unattended: false, credits: nil)
    seconds = [seconds.to_f, 0.0].max

    changes = { player_progress: seconds }
    # `completed` going true fires set_completed_at and set_last_watched_at, which stamp
    # the present -- right here, because this is somebody watching it now.
    if !completed? && !unattended && watched_enough?(seconds, duration, finished, credits)
      changes[:completed] = true
    end

    update!(changes)
  end

  # Where the player should pick up, or nil to start from the beginning.
  #
  # A film watched to the end reports back a position in its own credits, and resuming
  # there means pressing play and watching it finish. Past the completion mark it starts
  # again; a viewer who then stops halfway through the rewatch resumes there as normal.
  #
  # On a channel that skips credits, "the end" is where the channel moved them on -- which
  # is short of the file's own completion mark, and would otherwise reopen the entry there.
  def resume_position(credits: nil)
    return nil unless player_progress.to_f.positive?

    mark = completion_mark(credits: credits)
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

  def watched_enough?(seconds, duration, finished, credits)
    return true if finished

    mark = completion_mark(duration, credits: credits)
    mark.present? && seconds >= mark
  end

  # The position past which the film counts as watched, or nil when nothing here knows how
  # long it is. The catalogue's runtime is preferred over the player's reported duration:
  # it is the length of the film, while the player is timing whatever file it was handed,
  # ads and all.
  def completion_mark(duration = nil, credits: nil)
    minutes = entry.length.to_i
    runtime = minutes.positive? ? minutes * 60 : duration

    self.class.completion_mark_for(runtime, credits: credits)
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
