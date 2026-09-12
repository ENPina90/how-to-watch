require 'rails_helper'

# The phone view is a different shape from the full site rather than a squeezed copy: a
# list of channels, a grid of posters, and one field. It exists for putting something on a
# channel while out, marking something watched, and reading the listings.
RSpec.describe 'The phone view', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:phone) { { 'HTTP_USER_AGENT' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15' } }
  let(:desktop) { { 'HTTP_USER_AGENT' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' } }

  before { sign_in user }

  describe 'the home page' do
    let!(:favourites) { create(:list, user: user, name: 'My Favourites') }
    let!(:followed) { create(:list, user: user, name: 'Aardvark Cinema') }

    # Creating a channel subscribes its owner -- see List#auto_subscribe_owner -- so both
    # of these are already followed by the time the examples run.
    before { user.update!(favorite_list: favourites) }

    it 'lists the channels this member follows' do
      get lists_path, headers: phone

      expect(response).to be_successful
      expect(response.body).to include('Aardvark Cinema')
    end

    # Theirs whether or not they subscribe to it -- it is the channel "add to favourites"
    # writes into, so it has to be reachable from the page that lists their channels.
    it 'puts their own favourites first, subscribed to or not' do
      get lists_path, headers: phone

      expect(response.body.index('My Favourites')).to be < response.body.index('Aardvark Cinema')
    end

    it 'does not repeat the favourites when they follow it too' do
      expect(user.subscribed_lists).to include(favourites)

      get lists_path, headers: phone

      expect(response.body.scan(/data-name="my favourites"/).length).to eq(1)
    end

    # The field filters the rows already on screen rather than searching anything: a dozen
    # names in the page is not a question worth a round trip.
    it 'puts the bar in filtering mode' do
      get lists_path, headers: phone

      expect(response.body).to include('data-mobile-shell-mode-value="filter"')
    end
  end

  describe 'a channel' do
    let(:list) { create(:list, user: user, name: 'Aardvark Cinema') }
    let!(:entry) do
      create(:entry, list: list, name: 'The Death of Harvey', media: 'movie',
                     imdb: 'tt0000001', position: 1, plot: 'A film about Harvey.')
    end

    it 'draws its entries as cards that turn over' do
      get list_path(list), headers: phone

      expect(response).to be_successful
      expect(response.body).to include('m-card__flip')
      expect(response.body).to include('The Death of Harvey')
      expect(response.body).to include('A film about Harvey.')
    end

    # There is no play button anywhere in this half of the app.
    it 'offers nothing that plays' do
      get list_path(list), headers: phone

      expect(response.body).not_to include(watch_entry_path(entry))
    end

    it 'points the bar at this channel, so a result can be added to it' do
      get list_path(list), headers: phone

      expect(response.body).to include('data-mobile-shell-mode-value="search"')
      expect(response.body).to include(%(data-mobile-shell-list-id-value="#{list.id}"))
    end

    it 'offers the eye, which is most of what the phone view is for' do
      get list_path(list), headers: phone

      expect(response.body).to include('mobile-watched')
      expect(response.body).to include(%(data-mobile-watched-entry-id-value="#{entry.id}"))
    end
  end

  describe 'the listings' do
    let(:provider) do
      Source.create!(name: 'Primary', kind: 'imdb', active: true, position: 1,
                     templates: { 'movie' => 'https://p.test/movie?imdb=%{imdb}' })
    end
    let!(:channel) { create(:list, user: user, provider: provider, default: true, name: 'Channel One') }
    let!(:film) { create(:entry, list: channel, name: 'Late Show', media: 'movie', length: 90, position: 1, imdb: 'tt0000009') }

    it 'serves the grid as a page of its own' do
      get cable_listings_path, headers: phone

      expect(response).to be_successful
      expect(response.body).to include('tvguide__grid')
      expect(response.body).to include('TV Guide')
    end

    # On a full-sized screen the listings belong over the picture, which is where the guide
    # button puts them. There is nothing here the channel page does not do better.
    it 'sends a full-sized screen to the channel instead' do
      get cable_listings_path, headers: desktop

      expect(response).to redirect_to(cable_path)
    end

    # A listing that opens at midnight is a listing nobody asked for, and there is no clock
    # ticking on this page to place the line after the fact.
    it 'carries where the present is, so the page can open on it' do
      get cable_listings_path, headers: phone

      expect(response.body).to include('--guide-now-hours:')
      expect(response.body).to include('data-mobile-listings-target="nowLine"')
    end

    it 'puts the bar away, having nothing for it to do' do
      get cable_listings_path, headers: phone

      expect(response.body).to include('data-mobile-shell-mode-value="none"')
    end
  end
end
