# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Playback preferences', :needs_provider, type: :request do
  let(:user) { create(:user) }
  # Both on, so a preference of "never" has something to override rather than agreeing
  # with the channel by accident.
  let(:channel) { create(:list, user: user, auto_play: true, auto_next: true) }
  let(:entry) { create(:entry, list: channel, media: 'movie', imdb: 'tt0111161') }

  describe 'the form' do
    before { sign_in user }

    it 'offers all three answers, blank included' do
      get profile_path

      expect(response.body).to include('Follow each channel')
      expect(response.body).to include('Auto play')
      expect(response.body).to include('Auto next')
    end

    it 'records an answer' do
      patch profile_path, params: { user: { auto_play: 'false', auto_next: 'true' } }

      expect(user.reload.auto_play).to be false
      expect(user.auto_next).to be true
    end

    # The difference between "no" and "I have not said" is the whole point of the column
    # being nullable, so a blank must not arrive as false.
    it 'takes a blank answer as having no preference' do
      user.update!(auto_play: false)

      patch profile_path, params: { user: { auto_play: '' } }

      expect(user.reload.auto_play).to be_nil
    end
  end

  describe 'what the player does with them' do
    before { sign_in user }

    it 'follows the channel while the member has no preference' do
      get watch_entry_path(entry)

      expect(response.body).to include('autoplay=1')
    end

    it 'overrides a channel that autoplays' do
      user.update!(auto_play: false)

      get watch_entry_path(entry)

      expect(response.body).to include('autoplay=0')
    end

    it 'overrides a channel that does not' do
      channel.update!(auto_play: false)
      user.update!(auto_play: true)

      get watch_entry_path(entry)

      expect(response.body).to include('autoplay=1')
    end

    it 'keeps the up-next card off when the member has turned it off' do
      user.update!(auto_next: false)

      get watch_entry_path(entry)

      expect(response.body).not_to include('data-controller="auto-advance"')
    end

    it 'offers the up-next card on a channel that does not, when the member asks for it' do
      channel.update!(auto_next: false)
      user.update!(auto_next: true)

      get watch_entry_path(entry)

      expect(response.body).to include('data-controller="auto-advance"')
    end
  end

  # Nobody to have a preference, so the channel decides exactly as it did before.
  it 'leaves a signed-out viewer with the channel setting' do
    AppSetting.update_access_mode!('open')

    get watch_entry_path(entry)

    expect(response.body).to include('autoplay=1')
  end
end
