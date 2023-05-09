class RemoveYearFromEntries < ActiveRecord::Migration[7.0]
  def change
    remove_column :entries, :year, :string
  end
end
