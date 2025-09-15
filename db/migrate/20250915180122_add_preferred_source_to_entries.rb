class AddPreferredSourceToEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :entries, :preferred_source, :integer
  end
end
