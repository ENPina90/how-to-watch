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
    it 'frames the player once and nothing else' do
      get watch_only_entry_path(entry)

      expect(response.body.scan('<iframe').length).to eq(1)
    end

    it 'leaves out the channel furniture the watch page carries' do
      get watch_only_entry_path(entry)

      expect(response.body).not_to include('entriesSidebar')
      expect(response.body).not_to include('cinema-chrome')
      expect(response.body).not_to include('cinema-navigation')
    end

    # The preload is the prime suspect whenever a player misbehaves, so the page whose job
    # is to rule it out must not be able to start one.
    it 'cannot warm a second player, because it has no controller to do it with' do
      get watch_only_entry_path(entry)

      expect(response.body).not_to include('data-cinema-navigation-preload-value')
      expect(response.body).not_to include('importmap')
      expect(response.body).not_to include('application.js')
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
