class AddDetailsToSubentry < ActiveRecord::Migration[7.0]
  def change
    add_column :subentries, :rating, :string
    add_column :subentries, :length, :integer
  end
end
