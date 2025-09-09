class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :list, null: false, foreign_key: true, index: false
      t.datetime :subscribed_at, default: -> { 'CURRENT_TIMESTAMP' }

      t.timestamps
    end

    # Ensure a user can only subscribe to a list once
    add_index :subscriptions, [:user_id, :list_id], unique: true, name: 'idx_subscriptions_user_list'

    # Indexes for common queries
    add_index :subscriptions, :user_id, name: 'idx_subscriptions_user'
    add_index :subscriptions, :list_id, name: 'idx_subscriptions_list'
    add_index :subscriptions, :subscribed_at, name: 'idx_subscriptions_subscribed_at'
  end
end
