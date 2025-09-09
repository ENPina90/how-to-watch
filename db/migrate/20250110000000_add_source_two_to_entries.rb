class AddSourceTwoToEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :entries, :source_two, :string
  end
end
