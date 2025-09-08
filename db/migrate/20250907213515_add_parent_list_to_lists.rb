class AddParentListToLists < ActiveRecord::Migration[8.0]
  def change
    add_reference :lists, :parent_list, null: true, foreign_key: { to_table: :lists }
    add_column :lists, :position, :integer
    add_index :lists, [:parent_list_id, :position]
  end
end
