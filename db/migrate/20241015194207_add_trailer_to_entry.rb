class AddTrailerToEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :trailer, :string
  end
end
