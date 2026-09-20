require 'rails_helper'

# The isolated player: one entry, one frame, nothing else on the page.
#
# Its value is entirely in what it does *not* do, so that is what is asserted here. A page
# that quietly grew a sidebar, a preload or a write would still look right in a browser and
# would have stopped being a control -- which is the only thing it is for.
RSpec.describe 'Watching an entry in isolation', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list, name: 'Solaris', imdb: 'tt1', media: 'movie', position: 1) }

  before { sign_in user }

  it 'plays the entry on its resolved provider' do
    get watch_only_entry_path(entry)

    expect(response).to be_successful
    expect(response.body).to include('https://spec.test/movie/tt1')
  end

  describe 'isolation' do
    it 'leaves out the channel furniture the watch page carries' do
      get watch_only_entry_path(entry)

      expect(response.body).not_to include('entriesSidebar')
      expect(response.body).not_to include('cinema-chrome')
      expect(response.body).not_to include('cinema-navigation')
    end

    # The preload is the prime suspect whenever a player misbehaves, so the page that exists
    # to rule it out must never start one by itself. The rig below can put a second player
    # here by hand, which is a different thing: a control that can be turned into a
    # reproduction on purpose, and only on purpose.
    it 'warms nothing on its own, having no controller that could' do
      get watch_only_entry_path(entry)

      expect(response.body).not_to include('data-cinema-navigation-preload-value')
      expect(response.body).not_to include('importmap')
      expect(response.body).not_to include('application.js')
    end

    it 'renders exactly one frame before anybody presses anything' do
      get watch_only_entry_path(entry)

      expect(response.body.scan('<iframe').length).to eq(1)
    end
  end

  # Putting a second player on the page by hand, to find out whether that -- and not the
  # provider -- is what kills a film. What the watch page does five seconds after it loads,
  # here on a button.
  describe 'the second-player rig' do
    # Named so its slug maps to a real adapter in Source::SYNC_ADAPTERS. The shared spec
    # provider's does not, and a neighbour the watch page could never warm is one this rig
    # must not offer -- which is the rule being exercised here.
    let!(:warmable) do
      Source.create!(name: 'Vidsrc2', kind: 'imdb', active: true, position: 0,
                     templates: { 'movie' => 'https://vidsrc.test/movie/%{imdb}' },
                     autoplay_param: 'autoplay')
    end
    let!(:neighbour) do
      create(:entry, list: list, name: 'Mirror', imdb: 'tt9', media: 'movie',
                     provider: warmable, position: 2)
    end

    it 'offers something to put in the second frame' do
      get watch_only_entry_path(entry)

      expect(response.body).to include('id="hudAddSpare"')
      expect(response.body).to include('Mirror')
    end

    # A spare that sits on a play button decodes nothing, so it would prove the opposite of
    # what the rig is for.
    it 'gives every candidate an address that starts playing' do
      get watch_only_entry_path(entry)

      options = response.body.scan(/<option value="([^"]+)"/).flatten

      expect(options).not_to be_empty
      expect(options).to all(include('autoplay'))
    end

    # The entry itself is always on the list, and answers a question the neighbours cannot:
    # whether a second stream of any kind is enough, or only one on a provider that keeps
    # playing because it cannot be told to stop.
    it 'always offers the entry itself as well' do
      get watch_only_entry_path(entry)

      expect(response.body.scan(/data-name="([^"]+)"/).flatten).to include(entry.name)
    end

    it 'puts an entry named outright at the top of the list' do
      get watch_only_entry_path(entry, spare: neighbour.id)

      first = response.body[/data-name="([^"]+)"/, 1]

      expect(first).to eq(neighbour.name)
    end

    # A provider with no adapter never gets a spare frame on the watch page -- adapterFor
    # declines it -- so offering one here would reproduce something that does not happen.
    it 'leaves out a neighbour on a provider the watch page would never warm' do
      direct = Source.create!(name: 'Direct only', kind: 'direct', active: true, position: 3,
                              templates: { 'movie' => 'https://direct.test/%{source_key}' })
      create(:entry, list: list, name: 'Unwarmable', imdb: nil, source_key: 'abc',
                     provider: direct, media: 'movie', position: 3)

      get watch_only_entry_path(entry)

      expect(response.body).not_to include('Unwarmable')
    end
  end

  # Not merely "does not write the position the watch page writes" -- nothing at all, so a
  # long diagnostic session cannot be the thing that moved your place in a channel.
  describe 'writing nothing' do
    it 'records no position in the channel' do
      expect { get watch_only_entry_path(entry) }.not_to change(UserListPosition, :count)
    end

    it 'records nothing against the entry' do
      expect { get watch_only_entry_path(entry) }.not_to change(UserEntry, :count)
    end

    it 'records no episode, even for a series' do
      series = create(:entry, list: list, media: 'series', imdb: 'tt2', position: 2)
      Subentry.create!(entry: series, season: '1', episode: '1', name: 'Pilot')

      expect { get watch_only_entry_path(series) }.not_to change(UserEntryPosition, :count)
    end
  end

  describe 'the provider override' do
    let!(:other) do
      Source.create!(name: 'Second provider', kind: 'imdb', active: true, position: 2,
                     templates: { 'movie' => 'https://other.test/movie/%{imdb}' })
    end

    it 'plays the same entry on another provider it is eligible for' do
      get watch_only_entry_path(entry, source: other.id)

      expect(response.body).to include('https://other.test/movie/tt1')
    end

    # A hand-typed id is a typo as often as it is a choice, and the page says which
    # provider it ended up on -- so the wrong one is shown rather than refused.
    it 'ignores one the entry could not play on' do
      direct = Source.create!(name: 'Direct only', kind: 'direct', active: true, position: 3,
                              templates: { 'movie' => 'https://direct.test/%{source_key}' })

      get watch_only_entry_path(entry, source: direct.id)

      expect(response.body).to include('https://spec.test/movie/tt1')
    end
  end

  describe 'when there is nothing to play' do
    # The watch page redirects to the channel here. This one must not: which provider it
    # resolved to and what that built is most of what the page is asked.
    it 'renders the reason instead of redirecting' do
      nothing = create(:entry, list: list, media: 'movie', imdb: nil, position: 3)

      get watch_only_entry_path(nothing)

      expect(response).to be_successful
      expect(response.body).to include('Nothing to play')
    end
  end

  describe 'access' do
    it 'is closed to a stranger, whatever the access mode allows elsewhere' do
      AppSetting.update_access_mode!('open')
      sign_out user

      get watch_only_entry_path(entry)

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  # spec/requests/content_security_policy_spec.rb makes the same demand of the other pages
  # that carry an inline block; this one carries its whole diagnostic that way.
  it 'gives its inline script the response nonce' do
    get watch_only_entry_path(entry)

    nonce = response.headers['Content-Security-Policy-Report-Only'][/'nonce-([^']+)'/, 1]
    inline = response.body.scan(/<script(?![^>]*\bsrc=)([^>]*)>/).flatten

    expect(inline).not_to be_empty
    expect(inline).to all(include(%(nonce="#{nonce}")))
  end
end
