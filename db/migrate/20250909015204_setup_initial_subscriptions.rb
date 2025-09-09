class SetupInitialSubscriptions < ActiveRecord::Migration[8.0]
  def up
    # Auto-subscribe all users to default lists
    execute <<-SQL
      INSERT INTO subscriptions (user_id, list_id, subscribed_at, created_at, updated_at)
      SELECT users.id, lists.id, NOW(), NOW(), NOW()
      FROM users
      CROSS JOIN lists
      WHERE lists.default = true
      AND NOT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE subscriptions.user_id = users.id
        AND subscriptions.list_id = lists.id
      )
    SQL

    # Auto-subscribe users to their own public lists
    execute <<-SQL
      INSERT INTO subscriptions (user_id, list_id, subscribed_at, created_at, updated_at)
      SELECT lists.user_id, lists.id, NOW(), NOW(), NOW()
      FROM lists
      WHERE lists.private = false
      AND NOT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE subscriptions.user_id = lists.user_id
        AND subscriptions.list_id = lists.id
      )
    SQL

    # Auto-subscribe users to their own private lists (owners are always subscribed)
    execute <<-SQL
      INSERT INTO subscriptions (user_id, list_id, subscribed_at, created_at, updated_at)
      SELECT lists.user_id, lists.id, NOW(), NOW(), NOW()
      FROM lists
      WHERE lists.private = true
      AND NOT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE subscriptions.user_id = lists.user_id
        AND subscriptions.list_id = lists.id
      )
    SQL

    puts "Set up initial subscriptions for existing users and lists"
  end

  def down
    # Remove all auto-generated subscriptions
    execute "DELETE FROM subscriptions"
    puts "Removed all subscriptions"
  end
end
