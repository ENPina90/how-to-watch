class AddDetailsToEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :postion, :integer
    add_column :entries, :season, :integer
    add_column :entries, :episode, :integer
  end
end
