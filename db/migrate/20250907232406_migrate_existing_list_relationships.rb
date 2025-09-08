class MigrateExistingListRelationships < ActiveRecord::Migration[8.0]
  def up
    # Migrate existing parent_list_id relationships to the join table
    execute <<-SQL
      INSERT INTO list_relationships (parent_list_id, child_list_id, position, created_at, updated_at)
      SELECT parent_list_id, id, COALESCE(position, 1), created_at, updated_at
      FROM lists
      WHERE parent_list_id IS NOT NULL
    SQL
  end

  def down
    # Remove all relationships from the join table
    execute "DELETE FROM list_relationships"
  end
end
