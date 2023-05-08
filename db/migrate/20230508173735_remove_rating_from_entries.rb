class RemoveRatingFromEntries < ActiveRecord::Migration[7.0]
  def change
    remove_column :entries, :rating, :integer
  end
end
