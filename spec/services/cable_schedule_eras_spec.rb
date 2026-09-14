# frozen_string_literal: true

require 'rails_helper'

# The decades at the end of the cable dial. They are channels with no list behind them: what
# they play is the public catalogue from their years, and their schedule rows name them by key.
RSpec.describe CableEra do
  let(:user) { create(:user) }
  let!(:provider) do
    Source.create!(name: 'Primary', kind: 'imdb', active: true, position: 1,
                   templates: { 'movie' => 'https://p.test/movie?imdb=%{imdb}' })
  end
  let(:shelf) { create(:list, user: user, provider: provider, name: 'Shelf') }
  let(:eighties) { described_class.find('1980s') }
  let(:date) { Date.new(2026, 9, 10) }
  let(:midnight) { CableSchedule.zone.local(2026, 9, 10) }

  def film(name, year, imdb, list: shelf)
    create(:entry, list: list, name: name, media: 'movie', year: year, length: 90, imdb: imdb)
  end

  describe 'the decades' do
    it 'runs newest first, with the golden age last' do
      expect(described_class.all.map(&:name)).to eq(['20s', '10s', '00s', '90s', '80s', '70s', '60s', 'Golden Age'])
    end

    it 'counts everything from 1900 to 1959 as the golden age' do
      expect(described_class.find('golden-age').years).to eq(1900..1959)
    end

    # A key that could be cast to a number would let /cable/80s serve list 80.
    it 'is found by its key and by nothing that looks like a list id' do
      expect(described_class.find('1980s')).to eq(eighties)
      expect(described_class.find('80')).to be_nil
      expect(described_class.find(nil)).to be_nil
    end
  end

  describe 'what a decade plays' do
    it 'draws films from those years out of any public channel' do
      blade_runner = film('Blade Runner', 1982, 'tt0083658')
      elsewhere = film('Aliens', 1986, 'tt0090605', list: create(:list, user: create(:user), name: 'Other'))
      film('Heat', 1995, 'tt0113277')

      expect(eighties.entries).to contain_exactly(blade_runner, elsewhere)
    end

    it 'leaves out a private channel' do
      film('Hidden', 1984, 'tt0000001', list: create(:list, user: user, name: 'Mine', private: true))

      expect(eighties.entries).to be_empty
    end

    # Filed in two channels, a film should not come up twice as often -- and the copy filed
    # first is the one the guide links back to.
    it 'plays a film filed twice once, from the channel it was filed in first' do
      first = film('Blade Runner', 1982, 'tt0083658')
      film('Blade Runner', 1982, 'tt0083658', list: create(:list, user: user, name: 'Again'))

      expect(eighties.entries).to eq([first])
    end
  end

  describe 'on the dial' do
    let!(:channel) { create(:list, user: user, provider: provider, default: true, name: 'Channel One') }

    it 'comes after every channel, in order' do
      expect(CableSchedule.dial).to eq([channel] + described_class.all)
      expect(CableSchedule.dial_number(eighties)).to eq(1 + 5)
    end

    it 'is found by the id in its address, ahead of any list' do
      expect(CableSchedule.find_channel('1980s')).to eq(eighties)
      expect(CableSchedule.find_channel(channel.id.to_s)).to eq(channel)
    end

    it 'deals a day from the catalogue, naming the decade rather than a list' do
      blade_runner = film('Blade Runner', 1982, 'tt0083658')

      expect(CableSchedule.build_day!(eighties, date)).to be_positive

      slots = CableSlot.where(era: '1980s')
      expect(slots.pluck(:list_id).uniq).to eq([nil])
      expect(slots.pluck(:entry_id).uniq).to eq([blade_runner.id])
      expect(CableSchedule.on_air(eighties, at: midnight + 1.hour).entry).to eq(blade_runner)
    end

    # The same film can be on a channel and on its decade at once, and dealing one must not
    # touch the other's day.
    it "keeps a decade's day apart from a channel's" do
      film('Blade Runner', 1982, 'tt0083658', list: channel)
      CableSchedule.build_day!(channel, date)
      channel_rows = CableSlot.where(list: channel).pluck(:id)

      CableSchedule.build_day!(eighties, date)
      CableSchedule.redeal!(eighties, [date])

      expect(CableSlot.where(list: channel).pluck(:id)).to match_array(channel_rows)
      expect(CableSlot.where(era: '1980s')).to exist
    end

    it 'leaves a decade day that already exists alone' do
      film('Blade Runner', 1982, 'tt0083658')
      CableSchedule.build_day!(eighties, date)

      expect(CableSchedule.ensure_day!(eighties, date)).to eq(0)
    end

    it 'is off air when the catalogue has nothing from those years' do
      expect(CableSchedule.build_day!(described_class.find('1960s'), date)).to eq(0)
      expect(CableSchedule.on_air(described_class.find('1960s'), at: midnight + 1.hour)).to be_nil
    end

    it 'shows up in the guide and in what is on now, after the channels' do
      film('Blade Runner', 1982, 'tt0083658')
      CableSchedule.build_day!(eighties, date)

      rows = CableSchedule.guide(at: midnight + 1.hour)
      expect(rows.map { |row| row[:channel] }).to eq(CableSchedule.dial)
      expect(rows.find { |row| row[:channel] == eighties }[:slots]).not_to be_empty

      now = CableSchedule.on_air_now(at: midnight + 1.hour)
      expect(now.map { |row| row[:channel] }).to include(eighties)
      expect(now.find { |row| row[:channel] == eighties }[:number]).to eq(6)
    end

    it 'steps from the last channel into the decades' do
      expect(CableSchedule.sibling(channel, :next)).to eq(described_class.all.first)
      expect(CableSchedule.sibling(described_class.all.last, :next)).to eq(channel)
    end
  end

  describe 'the database' do
    let(:entry) { film('Blade Runner', 1982, 'tt0083658') }

    def slot(**owner)
      CableSlot.insert_all!([{ entry_id: entry.id, airs_on: date, starts_at: midnight,
                               ends_at: midnight + 90.minutes, position: 0,
                               created_at: Time.current, updated_at: Time.current, **owner }])
    end

    it 'refuses a slot on no channel' do
      expect { slot(list_id: nil, era: nil) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'refuses a slot on a list and a decade at once' do
      expect { slot(list_id: shelf.id, era: '1980s') }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
