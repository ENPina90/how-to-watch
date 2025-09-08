class CreateListRelationships < ActiveRecord::Migration[8.0]
  def change
    create_table :list_relationships do |t|
      t.references :parent_list, null: false, foreign_key: { to_table: :lists }, index: false
      t.references :child_list, null: false, foreign_key: { to_table: :lists }, index: false
      t.integer :position

      t.timestamps
    end

    # Add custom indexes
    add_index :list_relationships, [:parent_list_id, :child_list_id], unique: true, name: 'idx_list_rel_parent_child'
    add_index :list_relationships, [:parent_list_id, :position], name: 'idx_list_rel_parent_position'
    add_index :list_relationships, :child_list_id, name: 'idx_list_rel_child'
  end
end
