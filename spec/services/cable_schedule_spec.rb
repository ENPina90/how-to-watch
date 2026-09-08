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

  describe 'the guide window' do
    # It runs a full day, opening a couple of hours behind the present so there is
    # something to scroll back to, and it always opens on a half hour -- the columns are
    # :00 and :30, and a window starting at 7:47 would label every one of them oddly.
    let(:lead) { described_class::GUIDE_LEAD_HOURS.hours }

    it 'opens on the half hour containing now, less the lead-in' do
      window = described_class.guide_window(at: midnight + 7.hours + 47.minutes)

      expect(window.begin).to eq(midnight + 7.hours + 30.minutes - lead)
      expect(window.end).to eq(window.begin + described_class::GUIDE_HOURS.hours)
    end

    it 'opens on the hour when now is in its first half' do
      window = described_class.guide_window(at: midnight + 7.hours + 12.minutes)

      expect(window.begin).to eq(midnight + 7.hours - lead)
    end

    it 'covers a whole day' do
      window = described_class.guide_window(at: midnight + 7.hours)

      expect(window.end - window.begin).to eq(24.hours)
    end

    it 'keeps the present inside it, with the past behind and the rest ahead' do
      at = midnight + 7.hours + 47.minutes
      window = described_class.guide_window(at: at)

      expect(window).to cover(at)
      expect(at - window.begin).to be_within(30.minutes).of(lead)
    end

    # The schedule is one fixed zone so that everybody sees the same programme at once, but
    # what time that is belongs to whoever is reading the listing.
    it 'opens on the viewer\'s half hour, not the schedule\'s' do
      berlin = ActiveSupport::TimeZone['Europe/Berlin']
      window = described_class.guide_window(at: midnight + 7.hours, in_zone: berlin)

      expect(window.begin.time_zone).to eq(berlin)
      expect(window.begin.min).to eq(0).or eq(30)
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
