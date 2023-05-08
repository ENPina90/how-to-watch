class RemoveImdbRatingFromEntries < ActiveRecord::Migration[7.0]
  def change
    remove_column :entries, :imdb_rating, :integer
  end
end
