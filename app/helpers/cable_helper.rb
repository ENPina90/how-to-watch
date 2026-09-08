# frozen_string_literal: true

module CableHelper
  # Times on a cable channel are read off a clock, so they are shown in the zone the
  # schedule was laid out in rather than the server's. Every viewer sees the listing the
  # channel was actually built against.
  def cable_time(time)
    time.in_time_zone(CableSchedule.zone).strftime("%-l:%M %p").downcase
  end

  # What to call a programme in the listing: the episode where there is one, since "Veep"
  # three times in a row tells the viewer nothing about what is coming.
  def cable_programme_name(slot)
    return slot.entry.name unless slot.subentry

    "#{slot.entry.name} — S#{slot.subentry.season}E#{slot.subentry.episode} #{slot.subentry.name}".strip
  end
end
