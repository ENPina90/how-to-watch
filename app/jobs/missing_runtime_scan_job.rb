# frozen_string_literal: true

# Finds the entries with no runtime recorded, anywhere in the catalogue, fills in what TMDB
# knows, and tells admins about the rest.
#
# Weekly, and weekly is right: nothing changes here on its own. An entry arrives without a
# runtime because OMDB had none for it, and it stays that way until something fills it in.
# The reason to look regularly is that entries keep arriving -- a season imported on Tuesday
# can quietly hold a dozen episodes off the dial, and nothing on a channel says anything is
# missing from it.
#
# In that order, so a runtime TMDB could supply never becomes a notification somebody has
# to act on by hand.
class MissingRuntimeScanJob < ApplicationJob
  queue_as :default

  def perform
    backfill

    result = MissingRuntimeNotifier.call

    Rails.logger.info(
      "Missing runtime scan: #{result.missing} of #{result.checked} entries have no " \
      "runtime, #{result.created} notification(s) raised, #{result.removed} retired"
    )
  end

  private

  # A failure here -- TMDB down, or its key missing -- must not cost the admins their
  # notifications: it leaves the catalogue exactly as bare as it was, and the notifier
  # reports it as it stands.
  def backfill
    filled = RuntimeBackfill.call

    Rails.logger.info(
      "Missing runtime scan: filled #{filled.filled} of #{filled.checked} runtimes from TMDB"
    )
  rescue StandardError => e
    Rails.logger.error("Missing runtime scan: TMDB backfill failed: #{e.class}: #{e.message}")
  end
end
