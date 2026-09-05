# frozen_string_literal: true

# Finds the entries that frame up and say "This media is unavailable".
#
# Nobody here causes this and nobody here can see it coming: VidSrc's catalogue changes
# under the app, so an entry that played last week may have nothing behind it this week --
# and the embed still returns 200, so nothing surfaces it. That needs somebody to go and
# ask, and this is that somebody.
#
# Weekly, and after the poster scan rather than alongside it, so two sweeps are not making
# outbound requests at the same time.
class EmbedAvailabilityScanJob < ApplicationJob
  queue_as :default

  def perform
    result = UnplayableEmbedNotifier.call

    Rails.logger.info(
      "Embed availability scan: #{result.missing} of #{result.checked} entries unplayable, " \
      "#{result.created} notification(s) raised, #{result.removed} retired"
    )
  rescue EmbedAvailabilityAudit::CannotCheck => e
    # Not a failure worth retrying into: it means VidSrc itself is not answering, and the
    # next run is a week of provider weather away from this one.
    Rails.logger.warn("Embed availability scan skipped: #{e.message}")
  end
end
