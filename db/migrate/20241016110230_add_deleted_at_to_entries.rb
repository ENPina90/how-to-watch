class AddDeletedAtToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :deleted_at, :datetime
    add_index :entries, :deleted_at
  end
end
