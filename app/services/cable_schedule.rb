# frozen_string_literal: true

# The cable schedule: what every channel plays, all day, the same for everybody.
#
# A day is laid out once, in advance, by CableScheduleJob at noon. Entries are shuffled and
# laid end to end from midnight to midnight, each one pinned to a clock time. Turning a
# channel on does not start anything -- it joins whatever is already running, at the point
# it has already reached. That is the whole feature, and it is why nothing in here consults
# a user: two people opening the same channel at the same second must see the same frame.
#
# Contrast /watch, where every question is per-user: where you got to, what you have seen,
# which episode you are on. None of that applies here, and reading a schedule must never
# write any of it.
module CableSchedule
  # The zone the cable day runs in. Midnight-to-midnight here, not in UTC, so that a
  # schedule laid out "for tomorrow" means the viewer's tomorrow.
  DEFAULT_ZONE = "America/Toronto"

  # How long a programme runs when the catalogue has no runtime for it. A guess is better
  # than dropping the entry: a channel whose entries mostly lack runtimes would otherwise
  # go dark, and being a few minutes out only moves the boundary between two programmes.
  # Regenerated daily, so an error never accumulates.
  FALLBACK_MINUTES = { "movie" => 100, "fanedit" => 100 }.freeze
  FALLBACK_MINUTES_DEFAULT = 30

  # A programme has to be long enough to be worth pinning to a time. A runtime of one or
  # two minutes is nearly always bad catalogue data rather than a very short film, and a
  # day filled with them is thousands of rows.
  MIN_MINUTES = 5

  # How many days of played-out schedule to keep. Yesterday is worth having while somebody
  # is still watching a programme that started before midnight; anything older is history
  # nothing reads.
  RETAIN_DAYS = 2

  # A day is filled by taking entries from a shuffled bag and refilling it when it empties.
  # This caps how many programmes one day may hold, so a channel of two-minute clips that
  # slipped past MIN_MINUTES cannot write rows until the job times out.
  MAX_SLOTS_PER_DAY = 200

  module_function

  def zone = ActiveSupport::TimeZone[ENV.fetch("CABLE_TIME_ZONE", DEFAULT_ZONE)] || ActiveSupport::TimeZone[DEFAULT_ZONE]

  def now = Time.current.in_time_zone(zone)

  def today = now.to_date

  # The line-up: the channels /cable offers, in a fixed order so that "the channel below"
  # means the same thing to everybody and stays the same between page loads.
  #
  # Ordered by id rather than by name so that renaming a channel does not silently move it
  # in the dial, the way renaming a TV channel does not.
  def channels = List.where(default: true).order(:id)

  # The channel one step up or down the dial, wrapping at both ends. Nothing user-specific,
  # unlike List#find_sibling, which reads subscriptions and what you have already seen.
  def sibling(channel, direction)
    dial = channels.to_a
    at = dial.index { |list| list.id == channel.id }
    return dial.first if at.nil?

    dial[(at + (direction == :next ? 1 : -1)) % dial.length]
  end

  # What is on now. Nil when the channel has no schedule for this moment, which the page
  # renders as off air rather than as an error.
  def on_air(channel, at: Time.current)
    CableSlot.where(list: channel).on_air_at(at).includes(:entry, :subentry).first
  end

  # A full day of listings, scrollable. The visible width is a few hours; the rest is what
  # you scroll to, which is what the guide is for.
  GUIDE_HOURS = 24

  # How much of the window sits behind the present. Enough to scroll back and see what you
  # just missed, not so much that the day is mostly over before it starts.
  GUIDE_LEAD_HOURS = 2

  # The guide opens on a half hour, the way the printed listings did -- the columns are :00
  # and :30 and nothing else, so a window starting at 7:47 would label every one of them
  # with a time nobody recognises. The clock in the corner says what time it really is.
  #
  # In the viewer's own zone, not the schedule's. The schedule is a set of instants and is
  # laid out in one fixed zone so that every viewer sees the same programme at once; what
  # time that instant *is* belongs to whoever is looking. A listing whose columns disagreed
  # with the clock on the wall would be no use to read.
  def guide_window(at: Time.current, in_zone: zone)
    local = at.in_time_zone(in_zone)
    start = local.change(min: local.min < 30 ? 0 : 30, sec: 0, usec: 0) - GUIDE_LEAD_HOURS.hours

    start...(start + GUIDE_HOURS.hours)
  end

  # A viewer's zone name, or the schedule's own when it means nothing. Names come from the
  # browser, so they are checked rather than trusted -- and an unknown one is somebody's
  # unusual setup, not an error worth a page about.
  def resolve_zone(name)
    return zone if name.blank? || !name.match?(%r{\A[A-Za-z0-9_+\-/]{1,64}\z})

    ActiveSupport::TimeZone[name] || zone
  end

  # Every channel on the dial and what each is showing across that window, in one query
  # rather than one per channel: the whole point of the guide is seeing them together.
  #
  # A programme counts if any part of it falls inside the window, so the one already
  # running when the window opens is included -- that is the row the viewer is on.
  def guide(at: Time.current, in_zone: zone)
    window = guide_window(at: at, in_zone: in_zone)
    dial = channels.to_a
    by_channel = CableSlot.where(list_id: dial.map(&:id))
                          .where(starts_at: ...window.end)
                          .where(CableSlot.arel_table[:ends_at].gt(window.begin))
                          .includes(:entry, :subentry)
                          .in_order
                          .group_by(&:list_id)

    dial.each_with_index.map do |channel, index|
      # The number on the dial rather than the row's id: a channel is "12" because of where
      # it sits, and ids have gaps.
      { channel: channel, number: index + 1, slots: by_channel.fetch(channel.id, []) }
    end
  end

  # The cable days a window touches. The window is in the viewer's zone and `airs_on` is a
  # date in the schedule's, so the two have to be converted rather than compared.
  def days_covered(window)
    first = window.begin.in_time_zone(zone).to_date
    last = window.end.in_time_zone(zone).to_date

    (first..last).to_a
  end

  # Lay out one channel's day, replacing whatever was there. In a transaction because a
  # half-written day is worse than no day: the delete would have taken the old schedule off
  # air and left nothing in its place.
  def build_day!(channel, date)
    slots = plan(channel, date)

    CableSlot.transaction do
      CableSlot.where(list: channel, airs_on: date).delete_all
      CableSlot.insert_all!(slots) if slots.any?
    end

    slots.length
  end

  # Build only if that day is empty, so the job can be run twice and a page can ask for a
  # day nobody scheduled without wiping one that is already on air.
  def ensure_day!(channel, date)
    return 0 if CableSlot.where(list: channel, airs_on: date).exists?

    build_day!(channel, date)
  end

  # Yesterday's schedule is still worth having while a programme that started before
  # midnight is running; the week before last is rows nothing will ever read again.
  def prune!(before: today - RETAIN_DAYS)
    CableSlot.where(airs_on: ...before).delete_all
  end

  # ---- laying out a day ------------------------------------------------------------

  # The programmes of one day, as rows ready to insert.
  #
  # Entries are drawn from a shuffled bag and refilled when it runs out, which is what makes
  # a small channel repeat through the day without repeating in the same order. The one
  # thing the refill guards is playing the same entry twice in a row across the seam.
  def plan(channel, date)
    programmes = schedulable(channel)
    return [] if programmes.empty?

    day_start = zone.local(date.year, date.month, date.day)
    day_end = day_start + 1.day
    cursor = day_start
    bag = []
    last = nil
    rows = []

    while cursor < day_end && rows.length < MAX_SLOTS_PER_DAY
      bag = refill(programmes, last) if bag.empty?
      entry = bag.shift

      subentry = episode_for(entry)
      # An entry that cannot produce a playable URL is not a programme. Series are the
      # reason this is checked here rather than up front: the URL needs the episode, and
      # the episode is not chosen until the slot is.
      next if entry.embed_url(subentry: subentry).blank?

      finish = [cursor + runtime(entry), day_end].min
      rows << {
        list_id: channel.id, entry_id: entry.id, subentry_id: subentry&.id,
        airs_on: date, starts_at: cursor, ends_at: finish,
        position: rows.length, created_at: Time.current, updated_at: Time.current
      }

      last = entry
      cursor = finish
    end

    rows
  end

  # Everything the channel can play, including what it borrows from the channels inside it
  # -- the same reach the /watch arrows have. Preloaded because laying out a day asks every
  # one of them for a provider and a template, and the big channel holds 1,200.
  def schedulable(channel)
    entries = channel.watch_sequence.uniq
    ActiveRecord::Associations::Preloader.new(
      records: entries, associations: [:provider, :subentries, { list: :provider }]
    ).call

    entries.reject { |entry| entry.imdb.blank? && entry.source_key.blank? }
  end

  # A fresh shuffle, arranged so the seam between two bags does not play the same thing
  # twice running. With one programme to choose from there is nothing to arrange.
  def refill(programmes, last)
    bag = programmes.shuffle
    bag.push(bag.shift) if bag.length > 1 && bag.first == last

    bag
  end

  # Which episode of a series is on. Random, like everything else in the running order --
  # the channel is not working through a series in order, it is playing episodes of it.
  def episode_for(entry)
    return nil unless entry.media == "series" || entry.media == "anime"

    entry.subentries.to_a.sample
  end

  def runtime(entry)
    minutes = entry.length.to_i
    minutes = FALLBACK_MINUTES.fetch(entry.media, FALLBACK_MINUTES_DEFAULT) if minutes < MIN_MINUTES

    minutes.minutes
  end
end
