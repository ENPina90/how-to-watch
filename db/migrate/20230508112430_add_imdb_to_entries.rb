class AddImdbToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :imdb, :string
  end
end
