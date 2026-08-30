# frozen_string_literal: true

# Re-reads every linked member's Letterboxd diary and adds whatever is new.
#
# Fans out to one LetterboxdSyncJob per member rather than syncing inline: a member whose
# diary is unreadable should not stop the rest, and each sync is its own retryable unit.
class LetterboxdWeeklyRefreshJob < ApplicationJob
  queue_as :default

  # Every sync is at least one request to Letterboxd, so they are spread out rather than
  # arriving as one burst the moment the schedule fires.
  STAGGER = 20.seconds

  def perform
    scheduled = 0

    User.where(letterboxd_enabled: true).find_each do |user|
      # An account can be flagged but have lost the username the diary is read from.
      next unless user.letterboxd_ready?

      LetterboxdSyncJob.set(wait: scheduled * STAGGER).perform_later(user.id)
      scheduled += 1
    end

    Rails.logger.info("Letterboxd weekly refresh queued #{scheduled} syncs")
  end
end
