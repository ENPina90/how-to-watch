class UserEntryPosition < ApplicationRecord
  belongs_to :user
  belongs_to :entry
  belongs_to :current_subentry, class_name: 'Subentry', optional: true

  validates :user_id, uniqueness: { scope: :entry_id }

  # A player position recorded against one episode means nothing on the next one, so
  # changing episode starts the new one from the beginning rather than dropping the viewer
  # forty minutes into it. UserEntry holds one position per entry, not per episode, and
  # this is the one place the episode actually changes.
  after_update_commit :clear_player_progress, if: :saved_change_to_current_subentry_id?

  # Get or create position tracker for a user and entry
  def self.find_or_create_for(user, entry)
    find_or_create_by(user: user, entry: entry) do |position|
      # Start with first subentry
      first_subentry = entry.subentries.order(:season, :episode).first
      position.current_subentry = first_subentry
    end
  end

  # Advance to next episode.
  #
  # `from` is the episode the viewer is looking at, where the page knows it. It is usually
  # the stored one, but not after an episode runs out: the player moves the stored position
  # on as the credits start (EntriesController#progress), and the up-next card or the arrow
  # pressed a moment later means "the one after what I just watched" -- stepping from the
  # stored position instead would skip an episode.
  def advance_to_next!(from: current_subentry)
    return unless from

    # Asked of the entry rather than worked out here, so that warming the next episode and
    # actually moving to it can never disagree about which one it is.
    following = entry.subentry_after(from)
    following ||= from # At end, stay on last episode

    update!(current_subentry: following)
    following
  end

  # Go to previous episode. `from` as for advance_to_next!.
  def go_to_previous!(from: current_subentry)
    return unless from

    subentries = entry.subentries.order(:season, :episode)
    current_index = subentries.index(from)

    target = current_index && current_index > 0 ? subentries[current_index - 1] : from # At beginning, stay on first episode
    update!(current_subentry: target)
    target
  end

  # Set to specific subentry
  def update_to_subentry!(subentry)
    raise ArgumentError unless subentry.entry_id == entry_id
    update!(current_subentry: subentry)
  end

  private

  # update_all rather than a load-and-save: there is nothing to validate, and the row may
  # not exist at all for somebody who has never played this entry.
  def clear_player_progress
    UserEntry.where(user_id: user_id, entry_id: entry_id)
             .update_all(player_progress: nil, updated_at: Time.current)
  end
end
