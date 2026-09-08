# frozen_string_literal: true

# Finds the entries the cable schedule is guessing a length for.
#
# Weekly, and weekly is right: nothing changes here on its own. An entry arrives without a
# runtime because OMDB had none for it, and it stays that way until somebody types one in.
# The reason to look regularly is that entries keep arriving -- a season imported on Tuesday
# can put a dozen new guesses on the dial without anyone noticing until a programme starts
# over on a channel somebody was watching.
class MissingRuntimeScanJob < ApplicationJob
  queue_as :default

  def perform
    result = MissingRuntimeNotifier.call

    Rails.logger.info(
      "Missing runtime scan: #{result.missing} of #{result.checked} scheduled entries have no " \
      "runtime, #{result.created} notification(s) raised, #{result.removed} retired"
    )
  end
end
