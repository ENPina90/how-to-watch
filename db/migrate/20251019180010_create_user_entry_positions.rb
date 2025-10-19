class CreateUserEntryPositions < ActiveRecord::Migration[8.0]
  def change
    create_table :user_entry_positions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entry, null: false, foreign_key: true
      t.references :current_subentry, null: true, foreign_key: { to_table: :subentries }

      t.timestamps
    end

    add_index :user_entry_positions, [:user_id, :entry_id], unique: true
  end
end
