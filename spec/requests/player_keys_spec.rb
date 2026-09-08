# frozen_string_literal: true

require 'rails_helper'

# Fullscreen belongs to the container now rather than to the frame, so keystrokes land on
# this document instead of the player's and have to be forwarded. Without the controller
# mounted, the player's own shortcuts are simply gone.
RSpec.describe 'Player keyboard control', :needs_provider do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list, name: 'Gladiator') }

  it 'mounts the key handler on the frame the film is in' do
    sign_in user

    get watch_entry_path(entry)

    expect(response.body).to include('player-keys')
    expect(response.body).to include('data-player-keys-frame-value="cinema"')
  end

  # The adapter names which player protocol to speak, and there is only one that can be
  # driven at all -- a provider with no adapter gets no keys rather than dead ones.
  it 'names the adapter that drives the provider' do
    Source.create!(name: 'Framerelay', slug: 'framerelay', kind: 'imdb', active: true, position: 0,
                   templates: { 'movie' => 'https://framerelay.dev/embed/movie?imdb=%{imdb}' })
    sign_in user

    get watch_entry_path(entry)

    expect(response.body).to include('data-player-keys-adapter-value="vidsrc"')
  end

  it 'leaves the adapter empty for a provider with no player to talk to' do
    sign_in user

    get watch_entry_path(entry)

    expect(response.body).to include('data-player-keys-adapter-value=""')
  end

  # Pausing and seeking is watching rather than tracking, so it is not behind an account
  # the way position saving is.
  it 'gives a signed-out viewer the same keys when the site is open' do
    AppSetting.update_access_mode!('open')

    get watch_entry_path(entry)

    expect(response).to be_successful
    expect(response.body).to include('player-keys')
    expect(response.body).not_to include('player-progress')
  end

  it 'still mounts progress tracking alongside it for somebody signed in' do
    sign_in user

    get watch_entry_path(entry)

    expect(response.body).to include('data-controller="player-keys player-progress"')
  end
end
