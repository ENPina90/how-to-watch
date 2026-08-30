class AddLetterboxdSyncStateToUsers < ActiveRecord::Migration[8.0]
  def change
    # Whether the last diary sync worked, so the profile page can say so. Ticking the box
    # queues a background job, and if that job never runs -- no worker, dead Redis -- the
    # only signal was a channel that silently failed to appear.
    add_column :users, :letterboxd_synced_at, :datetime
    add_column :users, :letterboxd_sync_error, :string
  end
end
