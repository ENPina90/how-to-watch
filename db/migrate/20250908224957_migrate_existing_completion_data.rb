class MigrateExistingCompletionData < ActiveRecord::Migration[8.0]
  def up
    # Migrate existing completed entries to user_entries table
    # For each entry that is marked as completed, create a user_entry record
    # for the list owner (assuming list owner is the one who marked it completed)

    execute <<-SQL
      INSERT INTO user_entries (user_id, entry_id, completed, completed_at, created_at, updated_at)
      SELECT
        lists.user_id,
        entries.id,
        entries.completed,
        CASE
          WHEN entries.completed = true THEN entries.updated_at
          ELSE NULL
        END as completed_at,
        NOW(),
        NOW()
      FROM entries
      INNER JOIN lists ON entries.list_id = lists.id
      WHERE entries.completed IS NOT NULL
    SQL

    puts "Migrated completion data for #{Entry.count} entries"
  end

  def down
    # Remove all user_entries records (this will lose per-user tracking)
    execute "DELETE FROM user_entries"

    puts "Removed all user_entries records"
  end
end
