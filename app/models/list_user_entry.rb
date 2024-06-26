class ListUserEntry < ApplicationRecord
  belongs_to :list
  belongs_to :user
  belongs_to :current_entry, class_name: 'Entry', optional: true

  def reset_current(direction = nil)
    if  direction == :next && self.list.ordered == true
      history << self.current_entry.id
      next_entry = self.current_entry.next
      self.current_entry = next_entry.nil? ? reset_current : next_entry
    elsif direction == :next
      reset_current
    elsif direction == :previous
      self.current_entry = history.empty? ? reset_current : Entry.find(history.pop)
    else
      # random entry selected if no direction given
      self.current_entry = self.list.entries.sample
    end
    self.save
  end
end
