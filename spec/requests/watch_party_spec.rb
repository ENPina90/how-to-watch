require 'rails_helper'

RSpec.describe 'Watch parties' do
  let(:host)  { create(:user) }
  let(:guest) { create(:user) }
  let(:list)  { create(:list, user: host) }
  let(:entry) { create(:entry, list: list) }

  describe 'starting one' do
    it 'opens a party on what the host is watching and remembers it in the session' do
      sign_in host
      post watch_parties_path, params: { entry_id: entry.id, channel: list.id }

      party = WatchParty.open.last
      expect(party.host_user).to eq(host)
      expect(party.entry).to eq(entry)
      expect(session[:watch_party_token]).to eq(party.token)
    end
  end

  describe 'joining by token' do
    it 'puts the guest where the host is' do
      party = WatchParty.open_for(list: list, host: host, entry: entry)

      sign_in guest
      get watch_party_path(party.token)

      expect(response).to redirect_to(watch_entry_path(entry, channel: list.id, subentry: nil))
      expect(party.members).to include(guest)
    end

    it 'turns away a party that has ended rather than leaving a dead token in the session' do
      party = WatchParty.open_for(list: list, host: host, entry: entry)
      party.close!

      sign_in guest
      get watch_party_path(party.token)

      expect(response).to redirect_to(list_path(list))
      expect(session[:watch_party_token]).to be_nil
    end
  end

  describe 'leaving' do
    it 'ends the room when the host leaves it' do
      party = WatchParty.open_for(list: list, host: host, entry: entry)

      sign_in host
      delete watch_party_path(party.token)

      expect(party.reload).not_to be_open
    end

    it 'only removes the guest when a guest leaves' do
      party = WatchParty.open_for(list: list, host: host, entry: entry)
      party.join!(guest)

      sign_in guest
      delete watch_party_path(party.token)

      expect(party.reload).to be_open
      expect(party.members).not_to include(guest)
    end
  end

  describe 'the host moving' do
    # `watch` bails out before anything else when nothing can play the entry, and the room
    # is right not to follow the host to a page they were bounced off.
    let!(:source) do
      Source.create!(name: 'Test provider', slug: 'test-provider', kind: 'imdb', active: true,
                     position: 1, templates: { 'movie' => 'https://example.com/embed/%{imdb}' })
    end

    # The room follows the host by watching what their player page renders, so visiting a
    # different entry is what moves everyone -- there is no separate "advance" call.
    it 'moves the party when the host opens a different entry' do
      other = create(:entry, list: list, position: 2, name: 'Something else')
      party = WatchParty.open_for(list: list, host: host, entry: entry)

      sign_in host
      get watch_party_path(party.token)
      get watch_entry_path(other, channel: list.id)

      expect(party.reload.entry).to eq(other)
    end

    it 'does not let a guest move the room' do
      other = create(:entry, list: list, position: 2, name: 'Something else')
      party = WatchParty.open_for(list: list, host: host, entry: entry)

      sign_in guest
      get watch_party_path(party.token)
      get watch_entry_path(other, channel: list.id)

      expect(party.reload.entry).to eq(entry)
    end
  end
end
