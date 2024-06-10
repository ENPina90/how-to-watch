class ListUserEntry < ApplicationRecord
  belongs_to :list
  belongs_to :user
  belongs_to :current_entry, class_name: 'Entry', optional: true
end
