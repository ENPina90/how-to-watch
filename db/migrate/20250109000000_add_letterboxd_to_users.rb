class AddLetterboxdToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :letterboxd_access_token, :text
    add_column :users, :letterboxd_refresh_token, :text
    add_column :users, :letterboxd_token_expires_at, :datetime
    add_column :users, :letterboxd_user_id, :string
    add_column :users, :letterboxd_username, :string

    add_index :users, :letterboxd_user_id
  end
end
