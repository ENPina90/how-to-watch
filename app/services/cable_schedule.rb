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

  # Programmes end on the clock, not when the film happens to stop. A slot runs to the next
  # five-minute mark and whatever is left after the film has ended is a commercial break --
  # which means every slot also *starts* on a five-minute mark, and the listing reads the
  # way a listing should instead of 8:07, 9:53, 11:26.
  #
  # Runtimes are whole minutes and days start on the hour, so a break is 0, 1, 2, 3 or 4
  # minutes exactly. Never seconds, and never long enough to be worth showing in the guide.
  BREAK_GRID = 5.minutes

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
  # The order is `cable_position`, which an admin drags into place on /admin/cable. Not by
  # name -- renaming a channel must not silently move it in the dial, the way renaming a
  # television channel does not move it. Id order, which this used to be, had that property
  # too, but it is the order the rows happened to be created in and there was no way to
  # change it short of recreating a channel.
  #
  # `id` breaks the tie, which is also what carries a channel with no position at all:
  # null sorts last under a plain ASC in Postgres, so a channel marked default by some path
  # that does not set one lands at the end of the dial rather than the front of it.
  def channels = List.where(default: true).order(:cable_position, :id)

  # Put the dial in this order, given the channel ids from top to bottom.
  #
  # The whole order arrives at once rather than "this one moved to index N" -- the same
  # bargain Source.reorder! makes and for the same reason: there are a handful of channels,
  # so the saving is not worth having, and renumbering 1..N repairs any collision or gap
  # left by an earlier write as a side effect of the next drag.
  #
  # Ids that are not on the dial are ignored rather than rejected. A channel taken off in
  # another tab should not make the drag that is already on screen fail.
  def reorder_dial!(ids)
    ordered = ids.map(&:to_i).uniq
    on_dial = channels.pluck(:id).to_set

    List.transaction do
      ordered.select { |id| on_dial.include?(id) }.each_with_index do |id, index|
        List.where(id: id).update_all(cable_position: index + 1, updated_at: Time.current)
      end
    end
  end

  # Put a channel on the dial, at the end of it.
  #
  # `default` is the flag that decides what /cable offers, and setting it has a consequence
  # beyond cable: List#handle_default_subscription_changes subscribes every account to a
  # channel that becomes default, so this also puts the channel in everybody's sidebar.
  # That is existing behaviour and deliberate -- a channel on the dial is a channel the site
  # is offering everyone -- but it is worth knowing that the button does it.
  #
  # Today is laid out here rather than left to the next page load. Every page that reads
  # the schedule fills a day it finds empty, so the channel would not stay off air either
  # way; doing it now means the dial answers immediately instead of reading as off air
  # until somebody opens it. Tomorrow is left to the job, which deals it each morning --
  # it is not a day anybody can be looking at yet.
  def add_channel!(list)
    last = channels.maximum(:cable_position).to_i
    list.update!(default: true, cable_position: last + 1)

    ensure_day!(list, today)

    list
  end

  # Take a channel off the dial.
  #
  # Its slots are left where they are. They are unreachable -- every page under /cable reads
  # `channels` -- and prune! sweeps them within a couple of days, so deleting them here
  # would buy nothing except the case it would break: a channel put back on the dial the
  # same day keeps the day it was already playing rather than being dealt a new one on top
  # of viewers who were watching it.
  #
  # Subscriptions are left alone too, which is the same decision List makes when the flag
  # is cleared by any other path: being unsubscribed from a channel is something a member
  # does, not something that happens to them because an admin rearranged the dial.
  def remove_channel!(list)
    list.update!(default: false, cable_position: nil)

    list
  end

  # The number this channel answers to, counting from one. The guide's rows and the HUD's
  # badge both show it, so it is worked out in one place rather than by whoever is counting.
  def dial_number(channel)
    at = channels.to_a.index { |list| list.id == channel.id }

    at ? at + 1 : nil
  end

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

  # The whole dial as it stands this second: every channel that has something on, paired
  # with the slot it is showing and its number, in dial order. Channels that are off air are
  # simply absent -- there is nothing to say about them.
  #
  # Shaped like `guide`'s rows on purpose, and fetched in one query rather than one per
  # channel, because the sidebar's Now Playing card asks this on every page of the site that
  # draws a sidebar.
  #
  # A read, like the rest of cable: nothing here records that anybody looked.
  def on_air_now(at: Time.current)
    dial = channels.to_a
    return [] if dial.empty?

    playing = CableSlot.where(list_id: dial.map(&:id))
                       .on_air_at(at)
                       .includes(:entry, :subentry)
                       .index_by(&:list_id)

    dial.each_with_index.filter_map do |channel, index|
      slot = playing[channel.id]
      slot && { channel: channel, number: index + 1, slot: slot }
    end
  end

  # How much of the running order the HUD's arrows can step through without tuning: a
  # little of what has been, more of what is coming, because that is the direction anybody
  # asks about.
  NEARBY_BEFORE = 3
  NEARBY_AFTER = 5

  # The programmes either side of the one on air, for the arrows that show what came before
  # and what is on next. Returned as one run in order with the current programme among them,
  # so the page can step along it rather than work out where the middle is.
  def nearby(channel, at: Time.current)
    current = on_air(channel, at: at)
    return [] unless current

    slots = CableSlot.where(list: channel)
    before = slots.where(CableSlot.arel_table[:starts_at].lt(current.starts_at))
                  .order(starts_at: :desc).limit(NEARBY_BEFORE)
                  .includes(:entry, :subentry).to_a.reverse
    after = slots.where(CableSlot.arel_table[:starts_at].gt(current.starts_at))
                 .in_order.limit(NEARBY_AFTER)
                 .includes(:entry, :subentry).to_a

    before + [current] + after
  end

  # The guide is three cable days wide: yesterday, today and tomorrow, midnight to midnight.
  #
  # Whole days rather than a span of hours either side of now, because days are the unit the
  # schedule is written in -- a row in cable_slots belongs to an `airs_on` date -- and
  # because a listing you read by day should not begin and end in the middle of two of them.
  # Yesterday is as far back as is worth keeping: what was on last night is a question, what
  # was on last Tuesday is not. Tomorrow is as far forward as anything is laid out.
  GUIDE_BEHIND_DAYS = 1
  GUIDE_AHEAD_DAYS = 1

  # How many days of played-out schedule to keep, which is a restatement of the line above
  # rather than a number of its own -- and is declared here, next to it, so the two cannot
  # drift apart. A day the viewer can scroll to and the pruning has deleted is an empty row,
  # and nothing tells that apart from a channel that was off air. One day of margin on top,
  # for a guide left open across midnight.
  RETAIN_DAYS = GUIDE_BEHIND_DAYS + 1

  # The guide opens on a half hour, the way the printed listings did -- the columns are :00
  # and :30 and nothing else, so a window starting at 7:47 would label every one of them
  # with a time nobody recognises. The clock in the corner says what time it really is.
  #
  # In the viewer's own zone, not the schedule's. The schedule is a set of instants and is
  # laid out in one fixed zone so that every viewer sees the same programme at once; what
  # time that instant *is* belongs to whoever is looking. A listing whose columns disagreed
  # with the clock on the wall would be no use to read.
  # Midnight to midnight over the three days, in the schedule's own zone: cable days are
  # dates there, so which days to show is a question asked in that zone even though every
  # time printed on the grid is answered in the viewer's.
  #
  # `in_zone` is what the columns are labelled in and is not what decides the edges. The
  # window is the same three days for everybody -- it is the same schedule -- and a viewer
  # somewhere else reads it against their own clock, which is the whole of the difference.
  def guide_window(at: Time.current, in_zone: zone)
    today = at.in_time_zone(zone).to_date

    midnight_on(today - GUIDE_BEHIND_DAYS, in_zone)...midnight_on(today + GUIDE_AHEAD_DAYS + 1, in_zone)
  end

  # The instant a cable day begins, read in whichever zone the caller is going to print it
  # in. The same moment either way; `in_zone` only decides what it will be called.
  def midnight_on(date, in_zone = zone)
    zone.local(date.year, date.month, date.day).in_time_zone(in_zone)
  end

  # How wide the window is, in hours. The unit the grid is laid out in: every column, every
  # programme and the line marking now are all a multiple of one hour.
  def guide_hours(window) = (window.end - window.begin) / 3600.0

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
      # it sits, and ids have gaps. Same numbering as the HUD badge, by construction.
      { channel: channel, number: index + 1, slots: by_channel.fetch(channel.id, []) }
    end
  end

  # The cable days a window touches. The window is in the viewer's zone and `airs_on` is a
  # date in the schedule's, so the two have to be converted rather than compared.
  #
  # Read off the last instant inside the window rather than off its end, because the range
  # is half-open and the end now lands exactly on midnight every time -- so taking the end
  # at face value would claim a day the window stops at the very start of and never shows.
  def days_covered(window)
    first = window.begin.in_time_zone(zone).to_date
    last = (window.end - 1.second).in_time_zone(zone).to_date

    (first..last).to_a
  end

  # Of the days a window touches, the ones worth laying out: today and anything after it.
  #
  # A day that has been and gone is not filled in on demand. The listing for it is whatever
  # the channel actually played, and a schedule invented after the fact is not a record of
  # anything -- it is a plausible-looking day nobody watched, written into the past.
  # So the guide shows what was really there, and an empty stretch to the left is honest.
  def days_to_fill(window)
    days_covered(window).select { |date| date >= today }
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
  #
  # The clock is what ends this, not the bag: an entry that cannot be played moves nothing
  # on, so a channel where nothing can be played would fill bag after bag and never reach
  # the end of the day. A pass that places nothing is therefore the other way out -- see the
  # break below.
  def plan(channel, date)
    programmes = schedulable(channel)
    return [] if programmes.empty?

    day_start = zone.local(date.year, date.month, date.day)
    day_end = day_start + 1.day
    cursor = day_start
    # What the day before ended with, so this one does not open with it. The bag's rule
    # against playing the same thing twice running reaches only as far as the day it is
    # dealing, and the seam between two days is a place the viewer is actually sitting --
    # a film that runs to midnight and starts again is the most visible repeat there is.
    last = entry_before(channel, day_start)
    bag = refill(programmes, last)
    placed = false
    rows = []

    while cursor < day_end && rows.length < MAX_SLOTS_PER_DAY
      if bag.empty?
        # A whole pass over everything the channel has, and not one of them could be
        # played. Refilling would shuffle the same dead entries past the same check for
        # the rest of the day and never advance the clock by a second, so the channel is
        # off air instead -- which is a page saying so, rather than a request that never
        # returns.
        break unless placed

        bag = refill(programmes, last)
        placed = false
      end

      entry = bag.shift

      # An entry that cannot produce a playable URL is not a programme. Series are the
      # reason this is asked here rather than up front: the URL needs the episode, and the
      # episode is not chosen until the slot is.
      playable, subentry = playable_episode(entry)
      next unless playable

      # Where the film stops, and where the slot stops -- the same instant only when the
      # runtime happens to land on the grid.
      content_end = [cursor + runtime(entry, subentry), day_end].min
      finish = [next_break_mark(content_end), day_end].min
      rows << { list_id: channel.id, entry_id: entry.id, subentry_id: subentry&.id,
                airs_on: date, starts_at: cursor, ends_at: finish,
                position: rows.length, created_at: Time.current, updated_at: Time.current }
        .merge(commercial_break(entry, content_end, finish))

      placed = true
      last = entry
      cursor = finish
    end

    rows
  end

  # The programme this channel was showing as the day before ran out, where that day was
  # ever laid out. Read before the transaction that replaces this day, so it is the real
  # previous day rather than a half-written one -- and nil at the start of a channel's
  # history, which puts no constraint on the first programme of its first day.
  def entry_before(channel, day_start)
    CableSlot.where(list: channel)
             .where(ends_at: ..day_start)
             .order(ends_at: :desc)
             .first&.entry
  end

  # Everything the channel can play, including what it borrows from the channels inside it
  # -- the same reach the /watch arrows have. Preloaded because laying out a day asks every
  # one of them for a provider and a template, and the big channel holds 1,200.
  def schedulable(channel)
    entries = channel.watch_sequence.uniq
    ActiveRecord::Associations::Preloader.new(
      records: entries, associations: [:provider, :subentries, { list: :provider }]
    ).call

    entries.reject { |entry| unschedulable?(entry) }
  end

  # An entry with nothing to put in a template cannot be played, and one already known to be
  # broken should not be put on air to find out again -- a channel is watched rather than
  # worked through, so a dead programme is four minutes of black frame before the clock
  # moves the channel on by itself.
  #
  # `stream` is three-valued and only `false` means broken: it is nil for an entry nothing
  # has ever checked, and dropping those would take most of a young channel off the air on
  # no evidence. The same reading EmbedAvailabilityScanJob takes of the column.
  def unschedulable?(entry)
    return true if entry.imdb.blank? && entry.source_key.blank?

    entry.stream == false
  end

  # A fresh shuffle, arranged so the seam between two bags does not play the same thing
  # twice running. With one programme to choose from there is nothing to arrange.
  def refill(programmes, last)
    bag = programmes.shuffle
    bag.push(bag.shift) if bag.length > 1 && bag.first == last

    bag
  end

  # The next five-minute mark, or this one when the film ends exactly on it.
  def next_break_mark(time)
    step = BREAK_GRID.to_i / 60
    over = time.min % step
    return time if over.zero? && time.sec.zero?

    time.change(min: time.min - over, sec: 0) + step.minutes
  end

  # The gap after the film, and what fills it. Both the reel and the point it starts from
  # are decided here rather than when somebody tunes in: two people on the same channel at
  # the same second have to see the same advert, for the same reason they see the same film.
  #
  # A period with no reel -- or a film with no year -- still gets the gap. The page shows a
  # caption over it rather than a dead frame, which is what a channel with nothing to play
  # in the break would put up.
  def commercial_break(entry, content_end, finish)
    gap = (finish - content_end).to_i
    reel = CommercialReel.for_year(entry.year) if entry.year.present?

    # A reel is chosen for every slot, not only for the ones with a gap after them. The
    # catalogue's runtime is a claim, not a measurement -- it is missing for a good few
    # entries and simply wrong for others, and either way the film can end well before the
    # slot does. When that happens the page needs somewhere to go, and adverts from the
    # right year are a better answer than the last minutes of a film played twice.
    { break_starts_at: (content_end if gap.positive?),
      break_reel_id: reel&.id,
      break_offset: reel&.random_offset_for(gap) }
  end

  # Which episode of this entry is on, and whether there is one that can be played at all.
  #
  # Asked of every entry, because "can this be played" is only answerable once an episode is
  # picked -- a provider's series template wants a season and an episode number, and an
  # episode nobody numbered leaves it with a hole in it and no URL.
  #
  # Which is a fact about that episode and not about the show, so the rest are tried before
  # the show is passed over. That is also what makes a barren pass in `plan` mean what it is
  # taken to mean there: if nothing was placed, nothing on the channel can be played at all,
  # rather than the shuffle having been unlucky.
  def playable_episode(entry)
    episode_choices(entry).each do |episode|
      return [true, episode] if entry.embed_url(subentry: episode).present?
    end

    [false, nil]
  end

  # The episodes worth trying, in the order to try them. Random, like everything else in the
  # running order -- the channel is not working through a series in order, it is playing
  # episodes of it. A film has one candidate and it is the film itself.
  def episode_choices(entry)
    return [nil] unless entry.media == "series" || entry.media == "anime"

    entry.subentries.to_a.shuffle
  end

  def runtime(entry, subentry = nil) = fallback_minutes(entry, subentry).minutes

  # How long this programme is taken to run, in minutes.
  #
  # The episode's own runtime first, where one is playing: a show does not have a runtime,
  # its episodes do, and a season of forty-minute episodes laid out by the show's figure is
  # wrong for every one of them. Then the entry's own, then a flat guess.
  #
  # Public because the guess is worth naming: a warning about a missing runtime is more use
  # if it says what is being assumed in its place.
  def fallback_minutes(entry, subentry = nil)
    minutes = subentry&.length.to_i
    minutes = entry.length.to_i if minutes < MIN_MINUTES
    return minutes if minutes >= MIN_MINUTES

    FALLBACK_MINUTES.fetch(entry.media, FALLBACK_MINUTES_DEFAULT)
  end
end
