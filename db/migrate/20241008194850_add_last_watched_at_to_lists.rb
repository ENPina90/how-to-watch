class AddLastWatchedAtToLists < ActiveRecord::Migration[7.0]
  def change
    add_column :lists, :last_watched_at, :datetime
  end
end
