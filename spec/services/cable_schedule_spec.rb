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
