class AddSeriesImdbToEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :series_imdb, :string
  end
end
