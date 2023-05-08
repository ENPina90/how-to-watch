class RemoveDurationFromEntries < ActiveRecord::Migration[7.0]
  def change
    remove_column :entries, :duration, :integer
  end
end
