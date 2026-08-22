class LetterboxdBulkSyncJob < ApplicationJob
  queue_as :default

  # Letterboxd rate-limits, so the sync is paced. That pacing used to happen inside the
  # request — a user with 200 watched entries held a web thread for a minute and a half
  # and then hit the proxy timeout. Here the wait costs nothing but worker time.
  THROTTLE = 0.5

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.letterboxd_connected?

    synced = 0
    failed = 0

    user.user_entries.completed.includes(:entry).find_each do |user_entry|
      result = user.sync_entry_to_letterboxd!(user_entry.entry)

      if result[:error]
        failed += 1
        Rails.logger.warn "Letterboxd sync failed for entry #{user_entry.entry_id}: #{result[:message]}"
      else
        synced += 1
      end

      sleep(THROTTLE)
    end

    Rails.logger.info "Letterboxd bulk sync for user #{user_id}: #{synced} synced, #{failed} failed"
  end
end
