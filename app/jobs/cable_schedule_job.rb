# frozen_string_literal: true

# Lays out tomorrow's cable schedule, once a day at seven in the morning.
#
# Any hour but midnight would do, and the reason is the same whichever is picked: there is
# always a full day in hand. Whatever is on air this evening was laid out yesterday morning,
# so the day being written is never the day somebody is watching -- it has not started yet.
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
