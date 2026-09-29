# frozen_string_literal: true

require 'rails_helper'

# The guided tour, as far as the server takes part: whether it is drawn, which of its
# pages a visitor may reach, and that the elements its stops point at are still on those
# pages. The stops themselves run in the browser (tour_controller.js), where nothing here
# can reach them -- so the anchors are the part worth pinning down, since a renamed class
# or a dropped attribute would otherwise just skip a stop without anyone noticing.
RSpec.describe 'The guided tour', type: :request do
  let(:owner) { create(:user) }
  let!(:channel) { create(:list, user: owner, name: 'Movies to Watch Before You Die', private: false) }

  def config
    json = response.body[/data-tour-config-value="([^"]*)"/, 1]
    json && JSON.parse(CGI.unescapeHTML(json))
  end

  describe 'whether it is drawn' do
    before { AppSetting.update_access_mode!('open') }

    it 'is drawn when started with ?tour' do
      get root_path(tour: 1)

      expect(response.body).to include('data-controller="tour"')
    end

    it 'is drawn while the tour cookie says one is running' do
      cookies[:tour] = 'channel'

      get list_path(channel)

      expect(response.body).to include('data-controller="tour"')
    end

    it 'is not drawn otherwise' do
      get root_path

      expect(response.body).not_to include('data-controller="tour"')
    end

    it 'is not drawn on a phone' do
      get root_path(tour: 1), headers: { 'User-Agent' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile/15E148' }

      expect(response.body).not_to include('data-controller="tour"')
    end

    it 'keeps the welcome modal out of its way' do
      get root_path(tour: 1, welcome: 1)

      expect(response.body).not_to include('welcome-modal')
    end

    it 'is drawn on /cable, which has a layout of its own' do
      cookies[:tour] = 'cable'
      create_dial

      get cable_path

      expect(response.body).to include('data-controller="tour"')
    end
  end

  describe 'the pages it offers' do
    it 'offers all four to a member' do
      sign_in create(:user)

      get root_path(tour: 1)

      expect(config['pages']).to eq(%w[home channel results cable])
      expect(config['signedIn']).to be(true)
    end

    it 'offers a guest everything the open mode lets them reach' do
      AppSetting.update_access_mode!('open')

      get root_path(tour: 1)

      expect(config['pages']).to eq(%w[home channel results cable])
      expect(config['signedIn']).to be(false)
    end

    it 'leaves cable out where a guest may browse but not watch' do
      AppSetting.update_access_mode!('moderate')

      get root_path(tour: 1)

      expect(config['pages']).to eq(%w[home channel results])
    end

    it 'drops the channel pages when the example channel is private' do
      channel.update!(private: true)
      sign_in create(:user)

      get root_path(tour: 1)

      expect(config['pages']).to eq(%w[home cable])
    end

    it 'points at the example channel and the search inside it' do
      sign_in create(:user)

      get root_path(tour: 1)

      expect(config['paths']['channel']).to eq(list_path(channel))
      expect(config['paths']['results']).to eq(list_path(channel, query: 'Airplane!'))
      expect(config['text']['search']['title']).to be_present
    end
  end

  describe 'the elements its stops point at' do
    let(:member) { create(:user) }

    before { sign_in member }

    it 'finds the search, the sidebar and the community row on the home page' do
      create(:entry, list: channel, name: 'Airplane!', position: 1)

      get root_path

      expect(response.body).to include('id="navbar-search"', 'id="navShowType"', 'data-list-search-target="results"',
                                       'id="sidebarChannelsPanel"', 'data-tour="community"')
    end

    it 'finds the filters, the sections and the search on the channel page' do
      create(:entry, list: channel, name: 'Airplane!', year: 1980, position: 1)
      create(:entry, list: channel, name: 'Seven Samurai', year: 1954, position: 2)

      get list_path(channel, criteria: 'Year')

      expect(response.body).to include('data-tour="filters"', 'data-section-filter-target="option"',
                                       'class="section-toggle"', 'data-tour="channel-search"',
                                       'id="nowPlayingContent"')
    end
  end

  # A channel on the dial with a programme on air, so /cable renders a player. The same
  # shape cable_spec builds.
  def create_dial
    provider = Source.create!(name: 'Primary', kind: 'imdb', active: true, position: 1,
                              templates: { 'movie' => 'https://p.test/movie?imdb=%{imdb}' })
    channel.update!(provider: provider, default: true)
    create(:entry, list: channel, name: 'Airplane!', media: 'movie', length: 90, position: 1, imdb: 'tt0080339')
    CableSchedule.build_day!(channel, CableSchedule.today)
  end
end
