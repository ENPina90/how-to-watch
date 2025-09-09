class AddDefaultToLists < ActiveRecord::Migration[8.0]
  def change
    add_column :lists, :default, :boolean, default: false, null: false
    add_index :lists, :default
  end
end
