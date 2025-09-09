class CreateUserEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :user_entries do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :entry, null: false, foreign_key: true, index: false
      t.boolean :completed, default: false, null: false
      t.text :comment
      t.integer :review
      t.datetime :completed_at
      t.datetime :last_watched_at

      t.timestamps
    end

    # Ensure a user can only have one record per entry
    add_index :user_entries, [:user_id, :entry_id], unique: true, name: 'idx_user_entries_user_entry'

    # Indexes for common queries
    add_index :user_entries, :user_id, name: 'idx_user_entries_user'
    add_index :user_entries, :entry_id, name: 'idx_user_entries_entry'
    add_index :user_entries, [:user_id, :completed], name: 'idx_user_entries_user_completed'
    add_index :user_entries, [:user_id, :completed_at], name: 'idx_user_entries_user_completed_at'
    add_index :user_entries, [:user_id, :review], name: 'idx_user_entries_user_review'
  end
end
