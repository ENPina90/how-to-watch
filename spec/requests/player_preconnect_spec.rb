# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Warming the player connection', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list, media: 'movie', imdb: 'tt0111161') }

  # The slug is what maps a provider to its player (Source::SYNC_ADAPTERS), so a provider
  # with inner origins to warm has to be one of the real vidsrc slugs.
  def vidsrc_provider
    Source.create!(name: 'Vidsrc2', slug: 'vidsrc2', kind: 'imdb', active: true, position: 1,
                   templates: { 'movie' => 'https://vidsrc2.ru/embed/movie?imdb=%{imdb}' })
  end

  def direct_provider
    Source.create!(name: 'Drive', slug: 'google-drive', kind: 'direct', active: true, position: 2,
                   templates: { 'default' => 'https://drive.test/%{source_key}' })
  end

  before { sign_in user }

  it 'opens the front door early' do
    entry.update!(provider: vidsrc_provider)

    get watch_entry_path(entry)

    expect(response.body).to include('<link rel="preconnect" href="https://vidsrc2.ru">')
    expect(response.body).to include('<link rel="dns-prefetch" href="https://vidsrc2.ru">')
  end

  # The saving that actually matters: the browser cannot discover the inner frames until
  # the wrapper has loaded and parsed, so their whole handshake sits on the critical path.
  it 'opens the origins behind it, which the page could not otherwise discover' do
    entry.update!(provider: vidsrc_provider)

    get watch_entry_path(entry)

    expect(response.body).to include('<link rel="preconnect" href="https://cloudorchestranova.com">')
  end

  # A Drive embed never reaches for them, and a warmed socket nothing uses is a handshake
  # paid for nothing.
  it 'leaves a provider with no player of its own with just its own origin' do
    entry.update!(provider: direct_provider, source_key: 'abc123')

    get watch_entry_path(entry)

    expect(response.body).to include('<link rel="preconnect" href="https://drive.test">')
    expect(response.body).not_to include('cloudorchestranova.com')
  end

  # An iframe navigation is a credentialed load, and browsers pool those separately from
  # anonymous ones -- so `crossorigin` would warm a pool nothing goes on to use.
  it 'warms the pool the frame will actually use' do
    entry.update!(provider: vidsrc_provider)

    get watch_entry_path(entry)

    expect(response.body).not_to match(/<link rel="preconnect"[^>]*crossorigin/)
  end

  it 'says nothing for an entry with nothing to play' do
    entry.update!(provider: direct_provider, source_key: nil)

    get watch_entry_path(entry)

    # No source at all, so the page redirects rather than framing anything.
    expect(response).to have_http_status(:redirect)
  end

  describe PlayerHelper, type: :helper do
    it 'drops the port when it is the scheme default' do
      expect(helper.player_preconnect_origins('https://vidsrc2.ru:443/embed/movie', nil))
        .to eq(['https://vidsrc2.ru'])
    end

    it 'keeps a port that is not' do
      expect(helper.player_preconnect_origins('http://localhost:8080/embed', nil))
        .to eq(['http://localhost:8080'])
    end

    # Better to warm nothing than to emit a link to nowhere.
    it 'answers nothing for a url it cannot place' do
      expect(helper.player_preconnect_origins('not a url', nil)).to eq([])
      expect(helper.player_preconnect_origins(nil, nil)).to eq([])
      expect(helper.player_preconnect_origins('javascript:alert(1)', nil)).to eq([])
    end
  end
end
