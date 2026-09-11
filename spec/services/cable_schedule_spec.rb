require 'rails_helper'

# The cable schedule is the one part of the app that is the same for everybody. These are
# the properties that makes true: a day is covered end to end, what is on depends only on
# the clock, and laying one out reads no user state and writes none.
RSpec.describe CableSchedule do
  let(:user) { create(:user) }

  let!(:provider) do
    Source.create!(
      name: 'Primary', kind: 'imdb', active: true, position: 1,
      templates: {
        'movie' => 'https://p.test/movie?imdb=%{imdb}',
        'series' => 'https://p.test/tv?imdb=%{series_imdb}&s=%{season}&e=%{episode}'
      }
    )
  end

  let(:channel) { create(:list, user: user, provider: provider, default: true) }
  let(:date) { Date.new(2026, 9, 10) }
  let(:midnight) { described_class.zone.local(2026, 9, 10) }

  def film(name, minutes, position)
    create(:entry, list: channel, name: name, media: 'movie', length: minutes,
                   position: position, imdb: "tt#{position.to_s.rjust(7, '0')}")
  end

  describe 'laying out a day' do
    before { 3.times { |i| film("Film #{i}", 90, i + 1) } }

    it 'covers the whole day with no gap and no overlap' do
      described_class.build_day!(channel, date)
      slots = CableSlot.where(list: channel).in_order.to_a

      expect(slots.first.starts_at).to eq(midnight)
      expect(slots.last.ends_at).to eq(midnight + 1.day)
      slots.each_cons(2) { |a, b| expect(b.starts_at).to eq(a.ends_at) }
    end

    it 'runs each programme for its catalogue runtime' do
      described_class.build_day!(channel, date)

      # All but the last, which is cut off at midnight the way a real channel is.
      CableSlot.where(list: channel).in_order.to_a[0..-2].each do |slot|
        expect(slot.duration).to eq(90 * 60)
      end
    end

    it 'never plays the same entry twice running' do
      described_class.build_day!(channel, date)
      ids = CableSlot.where(list: channel).in_order.pluck(:entry_id)

      expect(ids.each_cons(2).any? { |a, b| a == b }).to be(false)
    end

    it 'replaces a day rather than adding to it' do
      described_class.build_day!(channel, date)
      before = CableSlot.where(list: channel, airs_on: date).count
      described_class.build_day!(channel, date)

      expect(CableSlot.where(list: channel, airs_on: date).count).to eq(before)
    end

    it 'leaves a day that already exists alone' do
      described_class.build_day!(channel, date)
      ids = CableSlot.where(list: channel, airs_on: date).in_order.pluck(:entry_id)

      expect(described_class.ensure_day!(channel, date)).to eq(0)
      expect(CableSlot.where(list: channel, airs_on: date).in_order.pluck(:entry_id)).to eq(ids)
    end
  end

  describe 'a day that is not 24 hours long' do
    before { 3.times { |i| film("Film #{i}", 90, i + 1) } }

    # Clocks go back on 2026-11-01 in America/Toronto and forward on 2026-03-08. A day laid
    # out by adding 24 hours to midnight would leave an hour of dead air on one and an hour
    # overlapping the next day's schedule on the other.
    {
      Date.new(2026, 11, 1) => 25.hours,
      Date.new(2026, 3, 8) => 23.hours
    }.each do |dst_date, length|
      it "fills #{dst_date} midnight to midnight (#{length.in_hours.to_i}h)" do
        described_class.build_day!(channel, dst_date)
        slots = CableSlot.where(list: channel, airs_on: dst_date).in_order.to_a
        start = described_class.zone.local(dst_date.year, dst_date.month, dst_date.day)

        expect(slots.first.starts_at).to eq(start)
        expect(slots.last.ends_at).to eq(start + 1.day)
        expect(slots.last.ends_at - slots.first.starts_at).to eq(length)
      end
    end
  end

  describe 'entries it will not schedule' do
    it 'skips anything that cannot produce a playable URL' do
      film('Playable', 90, 1)
      create(:entry, list: channel, name: 'Unplayable', media: 'movie', length: 90,
                     position: 2, imdb: nil, source_key: nil)

      described_class.build_day!(channel, date)

      expect(CableSlot.where(list: channel).map { |s| s.entry.name }.uniq).to eq(['Playable'])
    end

    # A channel is watched rather than worked through: a programme that cannot play is four
    # minutes of black frame before the clock moves the channel on by itself, and nobody
    # watching gets to skip it. So a link already reported broken stays off the air.
    it 'skips an entry whose stream is reported broken' do
      film('Working', 90, 1)
      create(:entry, list: channel, name: 'Broken', media: 'movie', length: 90,
                     position: 2, imdb: 'tt9999999', stream: false)

      described_class.build_day!(channel, date)

      expect(CableSlot.where(list: channel).map { |s| s.entry.name }.uniq).to eq(['Working'])
    end

    # Three-valued, and only false means broken. An entry nothing has ever checked is not
    # evidence of anything, and dropping those would take most of a young channel off air.
    it 'still schedules an entry nothing has checked yet' do
      create(:entry, list: channel, name: 'Unchecked', media: 'movie', length: 90,
                     position: 1, imdb: 'tt8888888', stream: nil)

      described_class.build_day!(channel, date)

      expect(CableSlot.where(list: channel).map { |s| s.entry.name }.uniq).to eq(['Unchecked'])
    end

    it 'gives a programme with no runtime a default rather than dropping it' do
      create(:entry, list: channel, name: 'Unknown length', media: 'movie', length: nil,
                     position: 1, imdb: 'tt1111111')

      described_class.build_day!(channel, date)

      expect(CableSlot.where(list: channel).first.duration).to eq(100 * 60)
    end

    it 'is off air when it can play nothing at all' do
      create(:entry, list: channel, media: 'movie', length: 90, position: 1, imdb: nil)

      expect(described_class.build_day!(channel, date)).to eq(0)
      expect(described_class.on_air(channel, at: midnight + 3.hours)).to be_nil
    end

    # An entry that cannot be played places no slot, so it moves the clock on by nothing.
    # A channel where that is true of every entry used to fill bag after bag against a day
    # that never got any shorter -- a request that never came back and a worker that never
    # freed up. It gives up and goes off air now, which is a page the viewer can read.
    #
    # Reached only by an entry the earlier filter lets through: one with an id but no
    # template to put it in, rather than one with no id at all.
    it 'gives up rather than spinning when nothing on the channel has a template' do
      create(:entry, list: channel, name: 'No template', media: 'documentary', length: 90,
                     position: 1, imdb: 'tt2222222')

      # Under a clock, because the failure this guards against is not a wrong answer but
      # no answer: without the guard in `plan` this call never returns and the example
      # would hang the suite rather than fail it.
      expect { Timeout.timeout(10) { described_class.build_day!(channel, date) } }
        .not_to raise_error

      expect(CableSlot.where(list: channel).count).to eq(0)
      expect(described_class.on_air(channel, at: midnight + 3.hours)).to be_nil
    end

    it 'still fills the day from the one entry that can be played' do
      film('Playable', 90, 1)
      create(:entry, list: channel, name: 'No template', media: 'documentary', length: 90,
                     position: 2, imdb: 'tt2222222')

      described_class.build_day!(channel, date)
      slots = CableSlot.where(list: channel).in_order.to_a

      expect(slots.first.starts_at).to eq(midnight)
      expect(slots.last.ends_at).to eq(midnight + 1.day)
      expect(slots.map { |slot| slot.entry.name }.uniq).to eq(['Playable'])
    end

    # A season or an episode number nobody filled in leaves the provider's template with a
    # hole in it and no URL, which says nothing about the other episodes of that show. A
    # channel holding one series would have gone off air for the day on an unlucky draw.
    it 'tries a show\'s other episodes before passing over the show' do
      series = create(:entry, list: channel, media: 'series', name: 'Show', length: nil,
                              position: 1, imdb: 'tt3333333')
      Subentry.create!(entry: series, season: nil, episode: nil, name: 'Unnumbered', length: 30)
      Subentry.create!(entry: series, season: 1, episode: 2, name: 'Numbered', length: 30)

      described_class.build_day!(channel, date)
      slots = CableSlot.where(list: channel).in_order.to_a

      expect(slots.first.starts_at).to eq(midnight)
      expect(slots.last.ends_at).to eq(midnight + 1.day)
      expect(slots.map { |slot| slot.subentry.name }.uniq).to eq(['Numbered'])
    end
  end

  describe 'what is on' do
    before do
      film('First', 60, 1)
      described_class.build_day!(channel, date)
    end

    it 'answers with the programme covering that instant, and how far into it' do
      slot = described_class.on_air(channel, at: midnight + 11.minutes)

      expect(slot.starts_at).to eq(midnight)
      expect(slot.offset_at(midnight + 11.minutes)).to eq(11 * 60)
    end

    it 'hands the boundary to the programme starting, not the one ending' do
      slot = described_class.on_air(channel, at: midnight + 1.hour)

      expect(slot.starts_at).to eq(midnight + 1.hour)
    end
  end

  # A show has no runtime of its own -- a season of forty-minute episodes and a season of
  # twenty-minute ones can sit under one entry, so there is no one figure to put on it. The
  # episode picked for the slot is the thing being laid out, and it has one.
  describe 'a series laid out by its episodes' do
    let(:series) do
      create(:entry, list: channel, media: 'series', name: 'Show', length: nil, position: 1,
                     imdb: 'tt0000001')
    end

    it 'takes the length of the episode it picked, not the show' do
      episode = Subentry.create!(entry: series, season: '1', episode: '1', name: 'Pilot',
                                 length: 53)
      series.update!(current: episode)

      described_class.build_day!(channel, date)
      slot = described_class.on_air(channel, at: midnight + 1.minute)

      expect(slot.subentry).to eq(episode)
      expect(slot.programme_duration).to eq(53 * 60)
    end

    # The flat guess is thirty minutes. An episode laid out by it runs on past the credits
    # or is cut off partway through, and both are visible on the channel.
    it 'falls back to the guess only where the episode has no length either' do
      Subentry.create!(entry: series, season: '1', episode: '1', name: 'Pilot', length: nil)

      expect(described_class.fallback_minutes(series, series.subentries.first)).to eq(30)
    end

    it 'prefers the episode over a length the show does carry' do
      series.update!(length: 30)
      episode = Subentry.create!(entry: series, season: '1', episode: '1', name: 'Pilot',
                                 length: 53)

      expect(described_class.fallback_minutes(series, episode)).to eq(53)
    end

    it 'falls back to the show when no episode is playing' do
      series.update!(length: 44)

      expect(described_class.fallback_minutes(series)).to eq(44)
    end
  end

  describe 'the dial' do
    let!(:other) { create(:list, user: user, provider: provider, default: true) }
    let!(:private_channel) { create(:list, user: user, provider: provider, default: false) }

    it 'is the default channels only' do
      expect(described_class.channels).to contain_exactly(channel, other)
    end

    it 'wraps at both ends' do
      dial = described_class.channels.to_a

      expect(described_class.sibling(dial.last, :next)).to eq(dial.first)
      expect(described_class.sibling(dial.first, :previous)).to eq(dial.last)
    end
  end

  # Programmes end on the clock rather than when the film happens to stop: a slot runs to
  # the next five-minute mark, and the gap after the film is a commercial break. Which also
  # means every slot starts on a five-minute mark, and the listing reads like a listing.
  describe 'padding a programme out to the clock' do
    let!(:reel) do
      CommercialReel.create!(label: '1987', starts_year: 1987, ends_year: 1987, youtube_id: 'abc')
    end

    def odd_film(minutes, position, year: 1987)
      create(:entry, list: channel, name: "Film #{position}", media: 'movie', length: minutes,
                     year: year, position: position, imdb: "tt000#{position.to_s.rjust(4, '0')}")
    end

    it 'starts every programme on a five-minute mark' do
      odd_film(47, 1)
      described_class.build_day!(channel, date)

      CableSlot.where(list: channel).in_order.each do |slot|
        local = slot.starts_at.in_time_zone(described_class.zone)
        expect(local.min % 5).to eq(0)
        expect(local.sec).to eq(0)
      end
    end

    it 'leaves no gap between one slot and the next' do
      odd_film(47, 1)
      described_class.build_day!(channel, date)

      CableSlot.where(list: channel).in_order.each_cons(2) do |a, b|
        expect(b.starts_at).to eq(a.ends_at)
      end
    end

    it 'marks the leftover as a commercial break' do
      odd_film(47, 1)
      described_class.build_day!(channel, date)
      slot = CableSlot.where(list: channel).in_order.first

      # 47 minutes from midnight ends at 00:47; the slot runs to 00:50.
      expect(slot.break_starts_at).to eq(midnight + 47.minutes)
      expect(slot.ends_at).to eq(midnight + 50.minutes)
      expect(slot.programme_duration).to eq(47 * 60)
    end

    # Runtimes are whole minutes and slots start on the mark, so a break is 1, 2, 3 or 4
    # minutes exactly -- never a stray number of seconds.
    it 'makes breaks a whole number of minutes, and never more than four' do
      odd_film(47, 1)
      odd_film(23, 2)
      odd_film(101, 3)
      described_class.build_day!(channel, date)

      CableSlot.where(list: channel).where.not(break_starts_at: nil).each do |slot|
        gap = (slot.ends_at - slot.break_starts_at).to_i
        expect(gap % 60).to eq(0)
        expect(gap).to be_between(60, 4 * 60).inclusive
      end
    end

    it 'gives a film that ends on the mark no break at all' do
      odd_film(45, 1)
      described_class.build_day!(channel, date)

      expect(CableSlot.where(list: channel).where.not(break_starts_at: nil)).to be_empty
    end

    it 'fills the break with adverts from the film\'s own year' do
      odd_film(47, 1, year: 1987)
      described_class.build_day!(channel, date)
      slot = CableSlot.where(list: channel).in_order.first

      expect(slot.break_reel).to eq(reel)
      expect(slot.break_offset).to be_present
    end

    # The break is still the break. The page puts a caption over it rather than a dead frame.
    it 'still leaves the gap when there are no adverts to put in it' do
      CommercialReel.delete_all
      odd_film(47, 1)
      described_class.build_day!(channel, date)
      slot = CableSlot.where(list: channel).in_order.first

      expect(slot.break_starts_at).to be_present
      expect(slot.break_reel).to be_nil
    end

    # The catalogue's runtime is a claim, not a measurement. It is missing for a fair number
    # of entries and simply wrong for others, so a film can end well before its slot does --
    # and a slot with no scheduled gap still needs somewhere to go when that happens.
    it 'chooses adverts for every slot, gap or no gap' do
      odd_film(45, 1)
      described_class.build_day!(channel, date)

      slots = CableSlot.where(list: channel)
      expect(slots.where(break_starts_at: nil)).to be_any
      expect(slots.where(break_reel_id: nil)).to be_empty
    end

    it 'starts a gapless slot\'s reel where it was told, steadily' do
      odd_film(45, 1)
      described_class.build_day!(channel, date)
      slot = CableSlot.where(list: channel).in_order.first

      expect(slot.break_starts_at).to be_nil
      expect(slot.reel_position_at(slot.starts_at + 5.minutes)).to eq(slot.break_offset)
      expect(slot.reel_position_at(slot.starts_at + 20.minutes)).to eq(slot.break_offset)
    end

    # Everybody on the channel has to be at the same advert, for the same reason they are
    # at the same point of the same film.
    it 'settles on one reel and one starting point when the day is laid out' do
      odd_film(47, 1)
      described_class.build_day!(channel, date)
      slot = CableSlot.where(list: channel).in_order.first

      at = slot.break_starts_at + 30.seconds
      expect(slot.reel_position_at(at)).to eq(slot.break_offset + 30)
      expect(slot.reel_position_at(at)).to eq(slot.reload.reel_position_at(at))
    end
  end

  describe 'the guide window' do
    # Three whole cable days, midnight to midnight: yesterday, today and tomorrow. Days
    # rather than a span of hours either side of now, because days are the unit the
    # schedule is written in and a listing read by day should not begin in the middle of one.

    it 'runs from the start of yesterday to the end of tomorrow' do
      window = described_class.guide_window(at: midnight + 7.hours)

      expect(window.begin).to eq(midnight - 1.day)
      expect(window.end).to eq(midnight + 2.days)
    end

    it 'is the same three days whatever time of day it is asked' do
      [1.minute, 7.hours, 22.hours, 23.hours + 59.minutes].each do |into_the_day|
        window = described_class.guide_window(at: midnight + into_the_day)

        expect(described_class.guide_hours(window)).to eq(72)
        expect(described_class.days_covered(window)).to eq([date - 1, date, date + 1])
      end
    end

    # Half-open, and the end lands exactly on midnight -- so taking it at face value would
    # claim a day the window stops at the very start of and never shows.
    it 'does not claim the day it stops at the start of' do
      window = described_class.guide_window(at: midnight + 7.hours)

      expect(described_class.days_covered(window).last).to eq(date + 1)
    end

    # The edges are the same instants for everybody: it is the same schedule, and a viewer
    # somewhere else reads it against their own clock. Only what the columns are *called*
    # belongs to the reader.
    it 'shows the same three days to a viewer in another zone' do
      berlin = ActiveSupport::TimeZone['Europe/Berlin']
      here = described_class.guide_window(at: midnight + 7.hours)
      there = described_class.guide_window(at: midnight + 7.hours, in_zone: berlin)

      expect(there.begin).to eq(here.begin)
      expect(there.end).to eq(here.end)
      expect(there.begin.time_zone).to eq(berlin)
    end

    # A day already played out is not laid out on demand: what was on is whatever was
    # really on, and a schedule invented afterwards is a day nobody watched written into
    # the past.
    it 'offers only today and later as days worth filling' do
      window = described_class.guide_window(at: midnight + 7.hours)

      travel_to(midnight + 7.hours) do
        expect(described_class.days_to_fill(window)).to eq([date, date + 1])
      end
    end

    it 'keeps the present inside it, with a day behind and a day ahead' do
      at = midnight + 7.hours + 47.minutes
      window = described_class.guide_window(at: at)

      expect(window).to cover(at)
      expect(window).to cover(at - 1.day)
      expect(window).to cover(at + 1.day)
    end

  end

  describe 'resolving a viewer\'s zone' do
    it 'takes a zone the browser knows' do
      expect(described_class.resolve_zone('Europe/Berlin').name).to eq('Europe/Berlin')
    end

    it 'falls back to the schedule\'s own for anything it does not recognise' do
      ['', nil, 'Mars/Olympus', '../../etc/passwd', 'a' * 200].each do |bad|
        expect(described_class.resolve_zone(bad)).to eq(described_class.zone)
      end
    end
  end

  describe 'the guide' do
    let!(:other) { create(:list, user: user, provider: provider, default: true, name: 'Two') }

    before do
      film('Long One', 90, 1)
      create(:entry, list: other, name: 'Short One', media: 'movie', length: 30,
                     position: 1, imdb: 'tt9999999')
      described_class.build_day!(channel, date)
      described_class.build_day!(other, date)
    end

    it 'numbers channels by where they sit on the dial, not by id' do
      rows = described_class.guide(at: midnight + 1.hour)

      expect(rows.map { |row| row[:number] }).to eq([1, 2])
      expect(rows.map { |row| row[:channel] }).to eq(described_class.channels.to_a)
    end

    it 'includes the programme already running when the window opens' do
      # The window opens at 01:00 and this channel runs one 90-minute film on a loop, so the
      # one starting at midnight is still on when the guide opens. Looked up by channel
      # rather than taken as the first row: the dial is ordered by id, and which of these
      # two got the lower one is an accident of how the spec is written.
      rows = described_class.guide(at: midnight + 1.hour)
      row = rows.find { |candidate| candidate[:channel] == channel }
      first = row[:slots].first

      expect(first.starts_at).to eq(midnight)
      expect(first.ends_at).to be > (midnight + 1.hour)
    end

    it 'stops at the end of the window' do
      window = described_class.guide_window(at: midnight + 1.hour)
      rows = described_class.guide(at: midnight + 1.hour)

      expect(rows.flat_map { |row| row[:slots] }).to all(have_attributes(starts_at: be < window.end))
    end

    it 'gives every channel on the dial a row, including one with nothing scheduled' do
      empty = create(:list, user: user, provider: provider, default: true, name: 'Empty')
      rows = described_class.guide(at: midnight + 1.hour)

      expect(rows.map { |row| row[:channel] }).to include(empty)
      expect(rows.find { |row| row[:channel] == empty }[:slots]).to be_empty
    end
  end

  describe 'the dial number' do
    let!(:other) { create(:list, user: user, provider: provider, default: true, name: 'Two') }

    it 'counts from one, in dial order' do
      dial = described_class.channels.to_a

      expect(described_class.dial_number(dial.first)).to eq(1)
      expect(described_class.dial_number(dial.last)).to eq(dial.length)
    end

    it 'is nil for a channel that is not on the dial' do
      off_dial = create(:list, user: user, provider: provider, default: false)

      expect(described_class.dial_number(off_dial)).to be_nil
    end

    # The guide's rows and the banner's badge must agree, or the same channel is two
    # different numbers depending on where you read it.
    it 'agrees with the number the guide gives each row' do
      film('One', 90, 1)
      described_class.build_day!(channel, date)

      rows = described_class.guide(at: midnight + 1.hour)

      rows.each { |row| expect(row[:number]).to eq(described_class.dial_number(row[:channel])) }
    end
  end

  describe 'the programmes either side of now' do
    before do
      film('Loop', 60, 1)
      described_class.build_day!(channel, date)
    end

    it 'returns a run with what is on air among it' do
      at = midnight + 6.hours
      run = described_class.nearby(channel, at: at)
      current = described_class.on_air(channel, at: at)

      expect(run).to include(current)
      expect(run).to eq(run.sort_by(&:starts_at))
    end

    it 'offers a little of the past and more of what is coming' do
      at = midnight + 6.hours
      run = described_class.nearby(channel, at: at)
      current = described_class.on_air(channel, at: at)
      at_index = run.index(current)

      expect(at_index).to eq(described_class::NEARBY_BEFORE)
      expect(run.length - at_index - 1).to eq(described_class::NEARBY_AFTER)
    end

    # Early in the day there is nothing behind it, and the run simply starts at the
    # beginning rather than padding itself out.
    it 'does not invent programmes before the schedule starts' do
      run = described_class.nearby(channel, at: midnight + 10.minutes)

      expect(run.first.starts_at).to eq(midnight)
    end

    it 'is empty for a channel that is off air' do
      CableSlot.delete_all

      expect(described_class.nearby(channel, at: midnight + 6.hours)).to be_empty
    end
  end

  describe 'pruning' do
    before do
      film('First', 60, 1)
      described_class.build_day!(channel, date)
    end

    it 'keeps recent days and drops older ones' do
      described_class.prune!(before: date)
      expect(CableSlot.where(list: channel, airs_on: date).count).to be_positive

      described_class.prune!(before: date + 1)
      expect(CableSlot.where(list: channel, airs_on: date).count).to be_zero
    end
  end
end
