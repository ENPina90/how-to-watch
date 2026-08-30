class AddLetterboxdEnabledToUsers < ActiveRecord::Migration[8.0]
  def change
    # Opting in is the whole of "linking an account": the RSS feed is public, so the
    # username already on `users` plus this flag is everything the sync needs.
    add_column :users, :letterboxd_enabled, :boolean, default: false, null: false

    # The weekly refresh selects on this, and almost nobody has it set.
    add_index :users, :letterboxd_enabled, where: 'letterboxd_enabled'
  end
end
