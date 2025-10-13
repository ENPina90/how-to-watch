class AddDarkModeToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :dark_mode, :boolean, default: true, null: false
  end
end
