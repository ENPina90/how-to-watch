# frozen_string_literal: true

module CableHelper
  # Times on a cable channel are read off a clock, so they are shown in the zone the
  # schedule was laid out in rather than the server's. Every viewer sees the listing the
  # channel was actually built against.
  def cable_time(time, zone = CableSchedule.zone)
    time.in_time_zone(zone).strftime("%-l:%M %p").downcase
  end

  # The clock in the guide's corner cell, seconds and all -- the old guides ran one, and it
  # is the only thing on the grid that says what time it actually is.
  def cable_clock(time, zone = CableSchedule.zone)
    time.in_time_zone(zone).strftime("%-l:%M:%S")
  end

  # The banner's headline: the episode's own name where there is one, since the show it
  # belongs to is said underneath rather than folded into the title.
  def cable_programme_headline(slot)
    slot.subentry&.name.presence || slot.entry.name
  end

  # The line under it -- what show this is, and when it is from. Only says what the headline
  # does not: a film gets its year, an episode gets the series it belongs to and its number.
  def cable_programme_context(slot)
    entry = slot.entry
    parts = []

    if slot.subentry
      parts << entry.name
      parts << if entry.media == "anime"
                 "E#{slot.subentry.calculate_absolute_episode_number}"
               else
                 "S#{slot.subentry.season}E#{slot.subentry.episode}"
               end
    elsif entry.media == "episode" && entry.series.present?
      parts << entry.series
      parts << "S#{entry.season}E#{entry.episode}" if entry.season.present? && entry.episode.present?
    end

    parts << entry.year if entry.year.present?
    parts.compact_blank.join(" · ")
  end

  # What to call a programme in the listing: the episode where there is one, since "Veep"
  # three times in a row tells the viewer nothing about what is coming.
  def cable_programme_name(slot)
    return slot.entry.name unless slot.subentry

    "#{slot.entry.name} — S#{slot.subentry.season}E#{slot.subentry.episode} #{slot.subentry.name}".strip
  end
end
