class AddDescriptionToLists < ActiveRecord::Migration[8.0]
  def change
    add_column :lists, :description, :text
  end
end
