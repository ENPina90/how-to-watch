# frozen_string_literal: true

# Finds the entries with no runtime recorded, anywhere in the catalogue.
#
# Weekly, and weekly is right: nothing changes here on its own. An entry arrives without a
# runtime because OMDB had none for it, and it stays that way until somebody types one in.
# The reason to look regularly is that entries keep arriving -- a season imported on Tuesday
# can quietly hold a dozen episodes off the dial, and nothing on a channel says anything is
# missing from it.
class MissingRuntimeScanJob < ApplicationJob
  queue_as :default

  def perform
    result = MissingRuntimeNotifier.call

    Rails.logger.info(
      "Missing runtime scan: #{result.missing} of #{result.checked} entries have no " \
      "runtime, #{result.created} notification(s) raised, #{result.removed} retired"
    )
  end
end
