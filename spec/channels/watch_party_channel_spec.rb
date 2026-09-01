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

  describe 'the last person leaving' do
    # Checked again after a grace period rather than on the spot: from here a reload looks
    # exactly like leaving, and closing the room under someone who is two seconds from
    # coming back is worse than one that lingers.
    it 'queues a check once nobody is left' do
      stub_connection current_user: host
      subscribe(token: party.token)

      expect { unsubscribe }.to have_enqueued_job(CloseAbandonedWatchPartiesJob)
    end

    it 'queues nothing while somebody is still there' do
      party.join!(guest)
      stub_connection current_user: host
      subscribe(token: party.token)

      expect { unsubscribe }.not_to have_enqueued_job(CloseAbandonedWatchPartiesJob)
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

  describe 'anyone stopping the film' do
    it 'lets a guest pause the room when the host allows it' do
      party.update!(player_status: 'playing', player_progress: 300.0, state_at: Time.current)
      stub_connection current_user: guest
      subscribe(token: party.token)

      expect { perform :control, 'status' => 'paused' }
        .to have_broadcasted_to(party).with(hash_including(action: 'control', status: 'paused'))
      expect(party.reload.player_status).to eq('paused')
    end

    # A pause carries no position of its own, so stopping the film cannot also drag the
    # room to wherever the person who pressed it happened to be sitting.
    it 'does not move the room to wherever the guest was' do
      party.update!(player_status: 'playing', player_progress: 300.0, state_at: Time.current)
      stub_connection current_user: guest
      subscribe(token: party.token)

      perform :control, 'status' => 'paused'

      expect(party.reload.player_progress).to be_within(2.0).of(300.0)
    end

    # The channel instance lives as long as the socket. Holding the party it loaded when
    # someone joined meant a guest carried on being allowed to stop the film after the
    # host had closed that off -- and that a pause was recorded against whatever position
    # was true when they arrived, which Active Record then wrote as no change at all.
    it 'refuses a guest the host closes off mid-film, without them reconnecting' do
      party.update!(player_status: 'playing')
      stub_connection current_user: guest
      subscribe(token: party.token)

      party.update!(guests_can_control: false)
      perform :control, 'status' => 'paused'

      expect(party.reload.player_status).to eq('playing')
    end

    it 'records the pause against where the room actually is, not where it was' do
      party.update!(player_status: 'playing', player_progress: 0.0, state_at: Time.current)
      stub_connection current_user: guest
      subscribe(token: party.token)

      # The host has been reporting all along; the guest's channel never saw any of it.
      party.update!(player_progress: 640.0, state_at: Time.current)
      perform :control, 'status' => 'paused'

      expect(party.reload.player_status).to eq('paused')
      expect(party.player_progress).to be_within(2.0).of(640.0)
    end

    it 'refuses a guest once the host has closed it off' do
      party.update!(guests_can_control: false, player_status: 'playing')
      stub_connection current_user: guest
      subscribe(token: party.token)

      perform :control, 'status' => 'paused'

      expect(party.reload.player_status).to eq('playing')
    end

    it 'still lets the host stop it when it is closed off' do
      party.update!(guests_can_control: false, player_status: 'playing')
      stub_connection current_user: host
      subscribe(token: party.token)

      perform :control, 'status' => 'paused'

      expect(party.reload.player_status).to eq('paused')
    end
  end

  describe 'who may stop the film' do
    it 'is the host\'s to change' do
      stub_connection current_user: host
      subscribe(token: party.token)

      perform :permission, 'allowed' => false

      expect(party.reload.guests_can_control).to be(false)
    end

    it 'is not a guest\'s to change' do
      stub_connection current_user: guest
      subscribe(token: party.token)

      perform :permission, 'allowed' => false

      expect(party.reload.guests_can_control).to be(true)
    end

    # A guest handed control mid-film has no way to know unless the room tells them.
    it 'reaches the room without a reload' do
      stub_connection current_user: host
      subscribe(token: party.token)

      expect { perform :permission, 'allowed' => false }
        .to have_broadcasted_to(party)
        .with(hash_including(action: 'settings', guests_can_control: false))
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
