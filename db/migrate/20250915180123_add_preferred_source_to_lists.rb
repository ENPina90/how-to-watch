class AddPreferredSourceToLists < ActiveRecord::Migration[8.0]
  def change
    add_column :lists, :preferred_source, :integer, default: 1
  end
end
