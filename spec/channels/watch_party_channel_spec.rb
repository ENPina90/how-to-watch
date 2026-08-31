require 'rails_helper'

RSpec.describe WatchPartyChannel, type: :channel do
  let(:host)  { create(:user) }
  let(:guest) { create(:user) }
  let(:list)  { create(:list, user: host) }
  let(:entry) { create(:entry, list: list) }
  let(:party) { WatchParty.open_for(list: list, host: host, entry: entry) }

  describe 'subscribing' do
    # transmit takes a positional hash. Called with bare keywords they bind to `via:`
    # instead, and subscribing raised ArgumentError -- so a guest joined the room, was
    # never handed its state, and sat on "Connecting..." forever.
    it 'hands the newcomer the room state' do
      party.update!(player_status: 'playing', player_progress: 90.0, state_at: Time.current)
      stub_connection current_user: guest

      subscribe(token: party.token)

      expect(subscription).to be_confirmed
      state = transmissions.find { |t| t['action'] == 'state' }
      expect(state['status']).to eq('playing')
      expect(state['progress']).to be_within(1.0).of(90.0)
    end

    it 'turns away a token with no open party behind it' do
      stub_connection current_user: guest

      subscribe(token: 'nonsense')

      expect(subscription).to be_rejected
    end
  end

  describe 'the host reporting in' do
    it 'records where the host is' do
      stub_connection current_user: host
      subscribe(token: party.token)

      perform :state, 'status' => 'playing', 'progress' => 120.5

      expect(party.reload.player_progress).to eq(120.5)
      expect(party.player_status).to eq('playing')
    end

    # The host never sends `heartbeat` -- that is the guests' message -- so nothing else
    # refreshes their presence, and they dropped out of their own room after 45 seconds.
    it 'counts as the host still being in the room' do
      stub_connection current_user: host
      subscribe(token: party.token)
      party.watch_party_memberships.find_by(user: host).update!(last_seen_at: 5.minutes.ago)

      perform :state, 'status' => 'playing', 'progress' => 10.0

      expect(party.present_memberships.map(&:user)).to include(host)
    end
  end

  describe 'a guest reporting in' do
    # The host's player is the room's clock. A guest that could post state would drag
    # everyone else to wherever they happen to be.
    it 'cannot move the room' do
      party.update!(player_progress: 500.0)
      stub_connection current_user: guest
      subscribe(token: party.token)

      perform :state, 'status' => 'playing', 'progress' => 10.0

      expect(party.reload.player_progress).to eq(500.0)
    end
  end
end
