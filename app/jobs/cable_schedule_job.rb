# frozen_string_literal: true

# Lays out tomorrow's cable schedule, once a day around noon.
#
# Noon rather than midnight so that there is always a full day in hand: whatever is on air
# this afternoon was scheduled yesterday lunchtime, and nothing is ever being written for a
# channel somebody is watching. The day being replaced is one that has not started.
#
# Today is filled in too, but only if it is empty -- the first run after a deploy, a
# channel newly marked default, a day the worker was down for. `ensure_day!` will not touch
# a schedule that already exists, so this cannot pull a running programme out from under
# anybody.
class CableScheduleJob < ApplicationJob
  queue_as :default

  def perform
    today = CableSchedule.today
    tomorrow = today + 1

    CableSchedule.channels.find_each do |channel|
      CableSchedule.ensure_day!(channel, today)
      CableSchedule.build_day!(channel, tomorrow)
    rescue StandardError => e
      # One channel with a bad entry must not cost every other channel its schedule --
      # a day nobody laid out is a day that channel is off air.
      Rails.logger.error("CableScheduleJob: #{channel.name} (#{channel.id}) failed: #{e.class}: #{e.message}")
    end

    CableSchedule.prune!
  end
end
