# frozen_string_literal: true

# Refreshes one member's Letterboxd channel from their public diary.
#
# Runs off the request: a sync is one RSS fetch plus a TMDB lookup for each film new to
# the channel, which is far too much to make somebody wait through when they tick the box.
#
# The outcome is recorded on the user because that is the only thing the profile page can
# report. Ticking the box queues this job, and if the job never runs -- no worker, dead
# Redis -- the only signal used to be a channel that silently failed to appear.
class LetterboxdSyncJob < ApplicationJob
  queue_as :default

  # Long enough to be useful in the UI, short enough for a string column.
  ERROR_LIMIT = 200

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.letterboxd_ready?

    result = LetterboxdList.new(user).sync!
    record_success(user)

    Rails.logger.info(
      "Letterboxd sync for user #{user_id}: #{result.created} added, " \
      "#{result.updated} updated, #{result.total} in feed"
    )
  rescue ActiveRecord::RecordNotFound
    # The account was deleted between the job being queued and running.
    nil
  rescue LetterboxdFeed::RequestError => e
    # A private profile, a renamed account or a Letterboxd outage. Not re-raised: none of
    # those is fixed by retrying, and the weekly run will try again anyway.
    record_failure(user, e)
    Rails.logger.warn("Letterboxd sync for user #{user_id} could not read the diary: #{e.message}")
  rescue StandardError => e
    # Anything unexpected is recorded so it is visible, then re-raised so the queue
    # retries it and reports it as a failure rather than swallowing it here.
    record_failure(user, e)
    raise
  end

  private

  # Written straight to the columns: an ordinary save would fire the user's own
  # after_commit, which queues a sync, which would arrive back here.
  def record_success(user)
    user.update_columns(letterboxd_synced_at: Time.current, letterboxd_sync_error: nil, updated_at: Time.current)
  end

  def record_failure(user, error)
    user&.update_columns(letterboxd_sync_error: error.message.truncate(ERROR_LIMIT), updated_at: Time.current)
  end
end
