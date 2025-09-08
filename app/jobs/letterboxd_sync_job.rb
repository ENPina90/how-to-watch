class LetterboxdSyncJob < ApplicationJob
  queue_as :default

  def perform(user_id, entry_id)
    user = User.find(user_id)
    entry = Entry.find(entry_id)

    return unless user.letterboxd_connected?

    result = user.sync_entry_to_letterboxd!(entry)

    if result[:error]
      Rails.logger.error("Background Letterboxd sync failed for user #{user_id}, entry #{entry_id}: #{result[:message]}")
    else
      Rails.logger.info("Successfully synced entry #{entry_id} to Letterboxd for user #{user_id}")
    end
  rescue StandardError => e
    Rails.logger.error("Letterboxd sync job failed: #{e.message}")
    raise e
  end
end
