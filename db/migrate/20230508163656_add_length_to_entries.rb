class AddLengthToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :length, :integer
  end
end
