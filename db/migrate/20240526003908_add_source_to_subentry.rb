class AddSourceToSubentry < ActiveRecord::Migration[7.0]
  def change
    add_column :subentries, :source, :string
  end
end
