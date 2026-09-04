class UserEntryPosition < ApplicationRecord
  belongs_to :user
  belongs_to :entry
  belongs_to :current_subentry, class_name: 'Subentry', optional: true

  validates :user_id, uniqueness: { scope: :entry_id }

  # Get or create position tracker for a user and entry
  def self.find_or_create_for(user, entry)
    find_or_create_by(user: user, entry: entry) do |position|
      # Start with first subentry
      first_subentry = entry.subentries.order(:season, :episode).first
      position.current_subentry = first_subentry
    end
  end

  # Advance to next episode
  def advance_to_next!
    return unless current_subentry

    subentries = entry.subentries.order(:season, :episode)
    current_index = subentries.index(current_subentry)

    if current_index && current_index < subentries.length - 1
      next_subentry = subentries[current_index + 1]
      update!(current_subentry: next_subentry)
      next_subentry
    else
      current_subentry # At end, stay on last episode
    end
  end

  # Go to previous episode
  def go_to_previous!
    return unless current_subentry

    subentries = entry.subentries.order(:season, :episode)
    current_index = subentries.index(current_subentry)

    if current_index && current_index > 0
      prev_subentry = subentries[current_index - 1]
      update!(current_subentry: prev_subentry)
      prev_subentry
    else
      current_subentry # At beginning, stay on first episode
    end
  end

  # Set to specific subentry
  def update_to_subentry!(subentry)
    raise ArgumentError unless subentry.entry_id == entry_id
    update!(current_subentry: subentry)
  end

end
