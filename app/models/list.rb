# frozen_string_literal: true

class List < ApplicationRecord

  belongs_to :user
  has_many :entries, dependent: :destroy
  has_many :list_user_entries
  has_many :users, through: :list_user_entries

  OFFSET = {
      previous: -1,
      current:   0,
      next:      1,
      # random:    rand(0...self.list.entries.count)
    }

  def self.like(name)
    where('name ILIKE ?', "%#{name}%").first
  end

  def watched!
    entry = find_entry_by_position(:next)
    self.update(current: entry.position)
  end

  def find_entry_by_position(change)
    return nil if entries.empty?

    # Determine the starting position.
    new_position = OFFSET.key?(change) ? current.to_i + OFFSET[change] : change.to_i

    # Ensure new_position falls within the min/max bounds of entry positions.
    min_position = entries.minimum(:position)
    max_position = entries.maximum(:position)
    new_position = min_position if new_position < min_position || new_position > max_position

    # Loop until we find a valid, not completed entry or exceed the maximum bound.
    while new_position <= max_position
      entry = entries.find_by(position: new_position)
      return entry if entry && !entry.completed
      new_position += 1
    end

    # Return nil if no valid entry is found.
    nil
  end


  def assign_current(change)
    new_position = OFFSET[change] ? self.current + OFFSET[change] : change
    update(current: new_position)
    Entry.find_by(list: self, position: new_position)
  end

  def find_sibling(change)
    lists = List.joins(:entries).where(entries: { completed: false }).distinct.where.not(current: nil).order(:created_at)
    # lists = List.where.associated(:entries).where.not(current: nil).order(:created_at)
    current_list_index = lists.index(self)
    return list.first unless current_list_index
    new_index = current_list_index + OFFSET[change]
    if new_index < 0
      lists.last
    elsif new_index >= lists.count
      lists.first
    else
      lists[new_index]
    end
  end
end
