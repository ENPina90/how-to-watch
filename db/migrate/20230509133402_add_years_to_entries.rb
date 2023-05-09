class AddYearsToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :years, :integer
  end
end
