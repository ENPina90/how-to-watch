require 'rails_helper'

RSpec.describe WatchParty do
  let(:host)  { create(:user) }
  let(:guest) { create(:user) }
  let(:list)  { create(:list, user: host) }
  let(:entry) { create(:entry, list: list) }

  describe '.open_for' do
    it 'closes whatever the host already had open' do
      first = described_class.open_for(list: list, host: host, entry: entry)
      second = described_class.open_for(list: list, host: host, entry: entry)

      expect(first.reload).not_to be_open
      expect(second).to be_open
    end

    it 'gives each party an unguessable token' do
      party = described_class.open_for(list: list, host: host, entry: entry)

      expect(party.token.length).to be >= 16
    end
  end

  describe '#projected_progress' do
    # The host's heartbeat is five seconds apart, so handing a late joiner the raw number
    # drops them up to five seconds behind the room.
    it 'ages a playing position forward by how long ago it was reported' do
      party = described_class.open_for(list: list, host: host, entry: entry)
      party.update!(player_status: 'playing', player_progress: 100.0, state_at: 4.seconds.ago)

      expect(party.projected_progress).to be_within(0.5).of(104.0)
    end

    it 'leaves a paused position where it was' do
      party = described_class.open_for(list: list, host: host, entry: entry)
      party.update!(player_status: 'paused', player_progress: 100.0, state_at: 30.seconds.ago)

      expect(party.projected_progress).to eq(100.0)
    end
  end

  describe 'presence' do
    it 'counts only people whose page has checked in recently' do
      party = described_class.open_for(list: list, host: host, entry: entry)
      party.join!(host)
      party.join!(guest)
      party.watch_party_memberships.find_by(user: guest).update!(last_seen_at: 5.minutes.ago)

      expect(party.present_memberships.map(&:user)).to contain_exactly(host)
    end

    it 'keeps the membership so returning needs no new invitation' do
      party = described_class.open_for(list: list, host: host, entry: entry)
      party.join!(guest)
      party.watch_party_memberships.find_by(user: guest).update!(last_seen_at: 5.minutes.ago)
      party.join!(guest)

      expect(party.present_memberships.map(&:user)).to include(guest)
    end
  end

  describe 'when the pubsub backend is unreachable' do
    # move_to! runs while the host's player page is rendering. A Redis that is down took
    # the whole page with it, so the host could not watch anything at all.
    it 'still moves the room, and does not take the page down' do
      party = described_class.open_for(list: list, host: host, entry: entry)
      other = create(:entry, list: list, position: 2, name: 'Something else')
      allow(WatchPartyChannel).to receive(:broadcast_to).and_raise(Redis::CannotConnectError)

      expect { party.move_to!(entry: other, subentry: nil, url: '/entries/2/watch') }
        .not_to raise_error
      expect(party.reload.entry).to eq(other)
    end

    it 'still closes the room' do
      party = described_class.open_for(list: list, host: host, entry: entry)
      allow(WatchPartyChannel).to receive(:broadcast_to).and_raise(Redis::CannotConnectError)

      expect { party.close! }.not_to raise_error
      expect(party.reload).not_to be_open
    end
  end

  describe 'destroying what it points at' do
    # Lists delete their entries with delete_all, so nothing in Rails clears the party;
    # only the database-level cascade keeps a channel deletable.
    it 'does not block deleting the channel an entry lives in' do
      other_list = create(:list, user: host)
      borrowed = create(:entry, list: other_list)
      described_class.open_for(list: list, host: host, entry: borrowed)

      expect { other_list.destroy }.not_to raise_error
      expect(described_class.count).to eq(0)
    end
  end
end
