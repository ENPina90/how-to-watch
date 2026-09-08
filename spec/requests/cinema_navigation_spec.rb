# frozen_string_literal: true

require 'rails_helper'

# Moving between entries happens in place: the page is fetched and pasted in rather than
# navigated to. That makes a handful of ids load-bearing -- they are how the incoming page
# is matched against the standing one -- and a rename would not fail anywhere. It would
# just quietly leave that part of the page describing the previous film.
RSpec.describe 'Moving between entries in place', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:channel) { create(:list, user: user, ordered: true) }
  let!(:entry) { create(:entry, list: channel, media: 'movie', imdb: 'tt0111161', position: 1) }
  let!(:next_entry) { create(:entry, list: channel, media: 'movie', name: 'The Next One', imdb: 'tt0068646', position: 2) }

  before { sign_in user }

  it 'marks every control that moves, and only those' do
    get watch_entry_path(entry)

    # Up and down are links to another channel; the three that record a position first are
    # forms. Five in total.
    expect(response.body.scan('data-cinema-move').length).to eq(5)
  end

  # The way home and the channel name are ordinary links out of the player, and have to
  # stay that way -- intercepting them would paste a channel page into the cinema screen.
  it 'leaves the way out of the player alone' do
    get watch_entry_path(entry)

    home = response.body[%r{<a[^>]*href="/"[^>]*>}]
    expect(home).to be_present
    expect(home).not_to include('data-cinema-move')
  end

  # The channel below is fetched before anybody asks for it, so that pressing down is
  # instant. Nothing about that fetch may look like a visit, because none of it has
  # happened yet as far as the viewer is concerned.
  describe 'warming the channel below' do
    let(:elsewhere) { create(:list, user: user, ordered: true) }
    let!(:over_there) { create(:entry, list: elsewhere, media: 'movie', name: 'Over There', imdb: 'tt0071562', position: 1) }

    def preload(path)
      get path, headers: { 'X-Cinema-Preload' => '1', 'X-Requested-With' => 'XMLHttpRequest' }
    end

    it 'marks the down arrow as the one worth warming' do
      get watch_entry_path(entry)

      expect(response.body.scan('data-cinema-preload').length).to eq(1)
    end

    it 'still renders the page it is asked for' do
      preload(watch_entry_path(over_there))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="cinema-chrome"')
    end

    # The whole point. An ordinary visit records where you are up to; a fetch of somewhere
    # you have not gone must not, or the app decides your place for you in a channel you
    # never opened.
    it 'does not move the viewer on in a channel they have not opened' do
      expect { preload(watch_entry_path(over_there)) }
        .not_to change { UserListPosition.where(user: user, list: elsewhere).count }.from(0)
    end

    it 'leaves a position that already exists where it was' do
      position = elsewhere.position_for_user!(user)
      position.update!(current_position: 99)

      preload(watch_entry_path(over_there))

      expect(position.reload.current_position).to eq(99)
    end

    it 'still records the position when somebody actually goes there' do
      get watch_entry_path(over_there)

      expect(elsewhere.position_for_user(user).current_position).to eq(over_there.position)
    end

    it 'is not counted as somebody arriving' do
      expect { preload(watch_entry_path(over_there)) }.not_to change { Visit.count }
    end

    # The host reading a player page is what moves everyone in a watch party onto it. A
    # page nobody has opened must not, or the room lands on a channel nobody chose and the
    # host is left the only one watching what they thought they all were.
    context 'with a watch party open' do
      # Through the controller, because the room is context carried in the session -- a
      # record on its own is not a party this request is in.
      let(:party) do
        post watch_parties_path, params: { entry_id: entry.id, channel: channel.id }
        WatchParty.open.find_by(host_user: user)
      end

      before { party }

      it 'does not move the room' do
        expect { preload(watch_entry_path(over_there)) }
          .not_to change { party.reload.entry_id }
      end

      it 'still moves the room when the host actually goes there' do
        expect { get watch_entry_path(over_there) }
          .to change { party.reload.entry_id }.to(over_there.id)
      end
    end
  end

  # How the warmed frame is quietened. cinema-navigation fetches the channel below, builds
  # its player in a second frame, and then has to stop it -- and it works out how from an
  # attribute on the fetched page. When that lookup comes back empty the frame is built
  # with nothing to drive it, so it plays on, out loud, behind the film being watched.
  #
  # It used to read player-progress's copy of the adapter name, which is only on the page
  # for somebody signed in and is not on the cable page at all. Nothing failed; the sound
  # just doubled. Hence an attribute of the player's own, on every page that has one.
  describe 'naming the adapter that drives the player' do
    it 'is on the watch page chrome' do
      get watch_entry_path(entry)

      expect(response.body).to include(%(data-player-adapter="#{playable_provider.sync_adapter}"))
    end

    it 'is on the cable page chrome' do
      channel.update!(default: true)
      CableSchedule.build_day!(channel, CableSchedule.today)

      get cable_channel_path(channel)

      expect(response.body).to include(%(data-player-adapter="#{playable_provider.sync_adapter}"))
    end

    # The reason it broke: it was inside the signed-in branch, next to the things that
    # record a position. Quietening a second player has nothing to do with having an
    # account, and a channel warmed by a signed-out visitor is just as loud.
    it 'is on the watch page for a visitor with no account' do
      sign_out user
      AppSetting.update_access_mode!('open')

      get watch_entry_path(entry)

      expect(response.body).to include(%(data-player-adapter="#{playable_provider.sync_adapter}"))
    end
  end

  describe 'the regions a move replaces' do
    it 'carries the chrome that describes this entry' do
      get watch_entry_path(entry)

      expect(response.body).to include('id="cinema-chrome"')
    end

    it 'carries the frame, addressed by a stable id' do
      get watch_entry_path(entry)

      expect(response.body).to include('<iframe id="cinema"')
    end

    it 'carries the entries sidebar' do
      get watch_entry_path(entry)

      expect(response.body).to include('id="entriesSidebar"')
    end

    # Drawn by the layout in the main sidebar, well outside the player page, and from the
    # same @entry -- so a move that forgets it leaves the previous film named there.
    it 'carries the now playing card, which the layout draws from the same entry' do
      get watch_entry_path(entry)

      expect(response.body).to include('id="nowPlayingContent"')
      expect(response.body).to include(entry.name)
    end

    # Also in the main sidebar and also drawn from @entry: it is the channel list, and the
    # highlight on it is on whichever channel is playing. A move between channels that
    # forgets this leaves the mark on the channel you just left.
    it 'carries the channel list, whose highlight follows the channel' do
      get watch_entry_path(entry)

      expect(response.body).to include('id="sidebarChannelsPanel"')
    end
  end
end
