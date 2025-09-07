class HandleParanoiaRemoval < ActiveRecord::Migration[8.0]
  def up
    # Option 1: Permanently delete all soft-deleted entries
    # Entry.where.not(deleted_at: nil).delete_all

    # Option 2: Restore all soft-deleted entries (recommended for safety)
    Entry.where.not(deleted_at: nil).update_all(deleted_at: nil)

    # Remove the deleted_at column and index since we're removing paranoia
    remove_index :entries, :deleted_at
    remove_column :entries, :deleted_at, :datetime
  end

  def down
    # Restore the deleted_at column if we need to rollback
    add_column :entries, :deleted_at, :datetime
    add_index :entries, :deleted_at
  end
end
