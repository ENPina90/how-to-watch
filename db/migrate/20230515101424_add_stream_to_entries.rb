class AddStreamToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :stream, :boolean
  end
end
