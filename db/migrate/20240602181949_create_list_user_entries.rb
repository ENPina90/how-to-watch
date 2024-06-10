class CreateListUserEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :list_user_entries do |t|
      t.references :list, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :current_entry, foreign_key: { to_table: :entries }
      t.integer :history, array: true, default: []

      t.timestamps
    end
  end
end
