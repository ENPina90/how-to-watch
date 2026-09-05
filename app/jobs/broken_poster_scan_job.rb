# frozen_string_literal: true

# Finds the posters that stopped loading since the last sweep.
#
# Nobody triggers this by editing anything: a poster that was there last week is gone this
# week because something happened at Cloudinary or at whatever host the pic column points
# at, not because the entry changed. That needs somebody to go and look, and this is that
# somebody. Weekly rather than daily -- it makes one HTTP request per entry, and a poster
# that has gone missing is not getting any more missing in the meantime.
class BrokenPosterScanJob < ApplicationJob
  queue_as :default

  def perform
    result = BrokenPosterNotifier.call

    Rails.logger.info(
      "Broken poster scan: #{result.broken} of #{result.checked} posters not loading, " \
      "#{result.created} notification(s) raised, #{result.removed} retired"
    )
  end
end
