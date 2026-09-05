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
  end
end
