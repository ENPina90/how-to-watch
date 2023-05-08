class AddRatingToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :rating, :float
  end
end
