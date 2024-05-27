class AddCurrentToEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :current_season, :integer
    add_column :entries, :current_episode, :integer
  end
end
