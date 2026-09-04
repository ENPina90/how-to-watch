# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Player progress', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list, media: 'movie', imdb: 'tt0111161', length: 100) }

  # The slug is what maps a provider to a player adapter (Source::SYNC_ADAPTERS), so a
  # provider that resumes has to be one of the real vidsrc slugs.
  def vidsrc_provider
    Source.create!(name: 'Vidsrc2', slug: 'vidsrc2', kind: 'imdb', active: true, position: 1,
                   autoplay_param: 'autoplay',
                   templates: { 'movie' => 'https://vidsrc2.ru/embed/movie?imdb=%{imdb}' })
  end

  # Drive and the rest hand the page no player to listen to, so nothing about them changes.
  def direct_provider
    Source.create!(name: 'Drive', slug: 'google-drive', kind: 'direct', active: true, position: 2,
                   templates: { 'default' => 'https://drive.test/%{source_key}' })
  end

  describe 'recording where the player reached' do
    before { sign_in user }

    it 'saves the position against this member and entry' do
      post progress_entry_path(entry), params: { progress: 742.5 }

      expect(response).to have_http_status(:no_content)
      expect(user.user_entry_for(entry).player_progress).to eq(742.5)
    end

    # The page that asks is usually already unloading, so there is nothing to send back.
    it 'answers with nothing at all' do
      post progress_entry_path(entry), params: { progress: 10 }

      expect(response.body).to be_empty
    end

    it 'starts tracking an entry this member has never touched' do
      expect { post progress_entry_path(entry), params: { progress: 10 } }
        .to change { UserEntry.where(user: user, entry: entry).count }.from(0).to(1)
    end

    it 'ticks the film off once the position is far enough through' do
      post progress_entry_path(entry), params: { progress: 5_700 }

      expect(user.user_entry_for(entry)).to be_completed
    end

    it 'ticks the film off when the player reports it finished' do
      post progress_entry_path(entry), params: { progress: 120, finished: 'true' }

      expect(user.user_entry_for(entry)).to be_completed
    end

    it 'leaves a film stopped part way through unwatched' do
      post progress_entry_path(entry), params: { progress: 600 }

      expect(user.user_entry_for(entry)).not_to be_completed
    end
  end

  # A write like any other: guests never get through, so a session that lapsed mid-film
  # records nothing rather than writing against whoever comes next.
  it 'records nothing for a signed-out viewer' do
    post progress_entry_path(entry), params: { progress: 742.5 }

    expect(response).to redirect_to(new_user_session_path)
    expect(UserEntry.count).to eq(0)
  end

  describe 'resuming on the next visit' do
    before { sign_in user }

    it 'starts a vidsrc embed where the player stopped' do
      entry.update!(provider: vidsrc_provider)
      user.user_entry_for!(entry).record_progress!(742.5)

      get watch_entry_path(entry)

      expect(response.body).to include('startAt=743')
    end

    it 'starts from the beginning for a member who has never played it' do
      entry.update!(provider: vidsrc_provider)

      get watch_entry_path(entry)

      expect(response.body).not_to include('startAt')
    end

    # A film seen to the end resumes at its own credits otherwise.
    it 'starts a finished film again' do
      entry.update!(provider: vidsrc_provider)
      user.user_entry_for!(entry).record_progress!(5_900)

      get watch_entry_path(entry)

      expect(response.body).not_to include('startAt')
    end

    # `startAt` is vidsrc's parameter; Drive would carry it as an ignored query string.
    it 'leaves a provider with no player to resume alone' do
      entry.update!(provider: direct_provider, source_key: 'abc123')
      user.user_entry_for!(entry).record_progress!(742.5)

      get watch_entry_path(entry)

      expect(response.body).not_to include('startAt')
    end

    it 'wires the tracking controller to the frame' do
      entry.update!(provider: vidsrc_provider)

      get watch_entry_path(entry)

      expect(response.body).to include('data-controller="player-progress"')
      expect(response.body).to include(progress_entry_path(entry))
    end

    # The client spots the credits starting for itself, to drop out of fullscreen without
    # waiting for a round trip. It has to reach the same answer the server would, so it is
    # given the same runtime and the same fraction rather than carrying its own copy.
    it 'hands the client the runtime and fraction the server judges completion by' do
      entry.update!(provider: vidsrc_provider, length: 100)

      get watch_entry_path(entry)

      expect(response.body).to include('data-player-progress-runtime-value="6000"')
      expect(response.body).to include(
        %(data-player-progress-fraction-value="#{UserEntry::COMPLETION_FRACTION}")
      )
    end

    # Then the player's own reported duration stands in, on both sides.
    it 'sends a zero runtime for an entry the catalogue has no length for' do
      entry.update!(provider: vidsrc_provider, length: nil)

      get watch_entry_path(entry)

      expect(response.body).to include('data-player-progress-runtime-value="0"')
    end

    # Nowhere to record a position, so the controller is left off rather than posting into
    # a sign-in redirect. The open access mode is what lets a stranger reach the player at
    # all -- without it this would pass on the sign-in page and prove nothing.
    it 'leaves the tracking controller off for a signed-out viewer' do
      AppSetting.update_access_mode!('open')
      entry.update!(provider: vidsrc_provider)
      sign_out user

      get watch_entry_path(entry)

      expect(response.body).to include('<iframe id="cinema"')
      expect(response.body).not_to include('player-progress')
    end
  end
end
