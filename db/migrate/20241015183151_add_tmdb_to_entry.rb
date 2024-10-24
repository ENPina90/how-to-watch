class AddTmdbToEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :tmdb, :string
  end
end
