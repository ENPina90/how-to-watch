# frozen_string_literal: true

class UserListPosition < ApplicationRecord
  belongs_to :user
  belongs_to :list

  validates :current_position, presence: true, numericality: { greater_than: 0 }
  validates :user_id, uniqueness: { scope: :list_id }

  # Find or create a user's position for a list
  def self.find_or_create_for(user, list)
    find_or_create_by(user: user, list: list) do |position|
      position.current_position = 1
    end
  end

  # Get the entry at the current position
  def current_entry
    list.entries.find_by(position: current_position)
  end

  # Move to next position (for ordered lists)
  def advance_to_next!
    next_entry = list.find_next_incomplete_entry_for_user(user, current_position)
    if next_entry
      update!(current_position: next_entry.position)
      next_entry
    else
      # No more incomplete entries, stay at current position
      current_entry
    end
  end

  # Steps on from an entry the player has just called watched, so that coming back to the
  # channel opens the next unwatched entry rather than replaying the one that just ended.
  #
  # Only while the position still points at that entry. The report that ticks it off is
  # often the one sent as the page goes away, and by the time it lands the viewer may
  # already be on the next entry -- or on one they picked by hand -- and the watch page has
  # recorded that. Moving on again from there would skip something they have not seen.
  #
  # An unordered channel is left alone: it shuffles on every visit and never offers a
  # watched entry, so there is nothing to step past. At the end of an ordered one the
  # position stays where it is, as advance_to_next! does.
  def move_past!(entry)
    return unless list.ordered?
    return unless current_position == entry.position

    following = list.find_next_incomplete_entry_for_user(user, entry.position)
    update!(current_position: following.position) if following
  end

  # Move to random incomplete position (for unordered lists)
  def advance_to_random!
    current_entry_obj = current_entry
    random_entry = list.find_random_incomplete_entry_for_user(user, current_entry_obj)
    if random_entry
      update!(current_position: random_entry.position)
      random_entry
    else
      # No more incomplete entries, stay at current position
      current_entry_obj
    end
  end

  # Update position to a specific entry
  def update_to_entry!(target_entry)
    update!(current_position: target_entry.position)
  end
end
