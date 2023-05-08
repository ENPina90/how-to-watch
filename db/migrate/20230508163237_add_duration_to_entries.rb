class AddDurationToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :duration, :integer
  end
end
