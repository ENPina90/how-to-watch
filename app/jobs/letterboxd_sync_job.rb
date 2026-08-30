# frozen_string_literal: true

# Refreshes one member's Letterboxd channel from their public diary.
#
# Runs off the request: a sync is one RSS fetch plus a TMDB lookup for each film new to
# the channel, which is far too much to make somebody wait through when they tick the box.
class LetterboxdSyncJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.letterboxd_ready?

    result = LetterboxdList.new(user).sync!
    Rails.logger.info(
      "Letterboxd sync for user #{user_id}: #{result.created} added, " \
      "#{result.updated} updated, #{result.total} in feed"
    )
  rescue LetterboxdFeed::RequestError => e
    # A private profile, a renamed account or a Letterboxd outage. The next run picks it
    # up; retrying here would only hammer a feed that is deliberately unreadable.
    Rails.logger.warn("Letterboxd sync for user #{user_id} could not read the diary: #{e.message}")
  end
end
