class RemoveLetterboxdOauthFromUsers < ActiveRecord::Migration[8.0]
  # Columns for an OAuth flow that could never run: the Letterboxd API is request-only and
  # is not granted for personal projects, so no credentials were ever issued and these
  # never held a value. The integration reads the public RSS feed instead, which needs a
  # username and nothing more. Reversible, so the columns come back if access is granted.
  def change
    remove_index :users, :letterboxd_user_id
    remove_column :users, :letterboxd_access_token, :text
    remove_column :users, :letterboxd_refresh_token, :text
    remove_column :users, :letterboxd_token_expires_at, :datetime
    remove_column :users, :letterboxd_user_id, :string
    remove_column :users, :letterboxd_username, :string
  end
end
