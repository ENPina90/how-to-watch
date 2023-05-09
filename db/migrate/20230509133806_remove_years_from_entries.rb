class RemoveYearsFromEntries < ActiveRecord::Migration[7.0]
  def change
    remove_column :entries, :years, :string
  end
end
