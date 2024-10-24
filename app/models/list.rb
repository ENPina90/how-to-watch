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
    redirect_to watch_entry_path(entry)
  end

  def find_entry_by_position(change)
    return nil if entries.empty?

    new_position = OFFSET[change] ? self.current + OFFSET[change] : change
    new_position = entries.minimum(:position) if new_position < 0 || new_position > entries.maximum(:position)

    # Find the entry by list and position
    entry = Entry.find_by(list: self, position: new_position)
    # Base case to prevent infinite recursion: stop when position exceeds bounds

    # Recursively find the next valid entry
    entry || find_entry_by_position(new_position + 1)
  end


  def assign_current(change)
    new_position = OFFSET[change] ? self.current + OFFSET[change] : change
    update(current: new_position)
    Entry.find_by(list: self, position: new_position)
  end

  def find_sibling(change)
    lists = List.where.not(current: nil).order(:created_at)
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
