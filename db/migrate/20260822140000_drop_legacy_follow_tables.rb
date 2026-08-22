# Both tables are superseded: `subscriptions` + `user_list_positions` replaced
# list_user_entries, and `follows` was never wired up to anything. Verified empty in
# production (0 rows in both) before writing this.
class DropLegacyFollowTables < ActiveRecord::Migration[8.0]
  def up
    drop_table :list_user_entries, if_exists: true
    drop_table :follows, if_exists: true
  end

  # Recreates the structure, not the data -- both tables were empty when dropped.
  def down
    create_table :list_user_entries do |t|
      t.bigint :list_id, null: false
      t.bigint :user_id, null: false
      t.bigint :current_entry_id
      t.integer :history, default: [], array: true
      t.timestamps
      t.index :current_entry_id
      t.index :list_id
      t.index :user_id
    end
    add_foreign_key :list_user_entries, :entries, column: :current_entry_id
    add_foreign_key :list_user_entries, :lists
    add_foreign_key :list_user_entries, :users

    create_table :follows do |t|
      t.bigint :user_id, null: false
      t.bigint :list_id, null: false
      t.timestamps
      t.index :list_id
      t.index :user_id
    end
    add_foreign_key :follows, :lists
    add_foreign_key :follows, :users
  end
end
