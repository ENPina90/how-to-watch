class CreateUserListPositions < ActiveRecord::Migration[8.0]
  def change
    create_table :user_list_positions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :list, null: false, foreign_key: true
      t.integer :current_position, default: 1

      t.timestamps
    end

    # Ensure each user can only have one position per list
    add_index :user_list_positions, [:user_id, :list_id], unique: true
  end
end
