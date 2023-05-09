class AddYearToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :year, :integer
  end
end
