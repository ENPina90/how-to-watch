class AddCompletedToSubentry < ActiveRecord::Migration[7.0]
  def change
    add_column :subentries, :completed, :boolean
  end
end
