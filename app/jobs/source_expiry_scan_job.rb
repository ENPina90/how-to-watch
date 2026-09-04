# frozen_string_literal: true

# Raises the expiry warnings nobody triggered by editing anything.
#
# Saving a source refreshes its own warnings, but the thing being warned about here is the
# calendar: a provider crosses into the warning window because a day passed, not because
# anyone touched it. That transition needs somebody to notice it, and this is that somebody.
class SourceExpiryScanJob < ApplicationJob
  queue_as :default

  def perform
    result = SourceExpiryNotifier.call

    return if result.created.zero? && result.removed.zero?

    Rails.logger.info(
      "Source expiry scan: #{result.created} warning(s) raised, #{result.removed} retired"
    )
  end
end
