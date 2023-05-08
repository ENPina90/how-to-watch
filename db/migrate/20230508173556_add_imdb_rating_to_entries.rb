class AddImdbRatingToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :imdb_rating, :float
  end
end
