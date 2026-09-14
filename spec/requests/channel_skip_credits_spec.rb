# frozen_string_literal: true

require 'rails_helper'

# A channel saying its programmes end before the file does. Everything that asks "is this
# over?" moves to that point together -- the completion mark, the resume cutoff and the
# up-next card -- because the card moves the channel on and moving on ticks nothing off: a
# mark left at the end of the file would be one an auto-advancing viewer never reached.
RSpec.describe 'Skipping a channel\'s credits', type: :request do
  let(:user) { create(:user) }
  let(:channel) { create(:list, user: user, auto_next: true) }

  # Only a provider whose player talks to the page tracks a position (Source::RESUME_PARAMS).
  let!(:provider) do
    Source.create!(name: 'Vidsrc2', slug: 'vidsrc2', kind: 'imdb', active: true, position: 1,
                   templates: { 'movie' => 'https://vidsrc2.ru/embed/movie?imdb=%{imdb}' })
  end

  # 100 minutes: 6,000 seconds, completion at 5,700. Ten minutes of credits skipped puts the
  # programme's end at 5,400 and its completion mark at 5,130.
  let(:entry) { create(:entry, list: channel, media: 'movie', imdb: 'tt0111161', length: 100) }

  describe 'the setting' do
    before { sign_in user }

    it 'is offered on the channel edit form' do
      get edit_list_path(channel)

      expect(response.body).to include('name="list[skip_credits_seconds]"')
      expect(response.body).to include('Skip credits')
    end

    it 'records an answer' do
      patch list_path(channel), params: { list: { skip_credits_seconds: '90' } }

      expect(channel.reload.skip_credits_seconds).to eq(90)
    end

    it 'takes a cleared field as playing to the end' do
      channel.update!(skip_credits_seconds: 90)

      patch list_path(channel), params: { list: { skip_credits_seconds: '' } }

      expect(channel.reload.skip_credits_seconds).to be_nil
    end

    it 'refuses a negative skip' do
      patch list_path(channel), params: { list: { skip_credits_seconds: '-5' } }

      expect(channel.reload.skip_credits_seconds).to be_nil
    end
  end

  describe 'what the page carries' do
    before { sign_in user }

    it 'hands the player the channel\'s credits' do
      channel.update!(skip_credits_seconds: 600)

      get watch_entry_path(entry)

      expect(response.body).to include('data-player-progress-credits-value="600"')
    end

    it 'hands it nothing to skip while the channel has no opinion' do
      get watch_entry_path(entry)

      expect(response.body).to include('data-player-progress-credits-value="0"')
    end

    # The server judges completion by the channel's skip, so it has to know which channel.
    it 'reports progress against the channel being watched from' do
      get watch_entry_path(entry)

      expect(response.body).to include(progress_entry_path(entry, channel: channel.id))
    end
  end

  describe 'when the entry counts as watched' do
    before { sign_in user }

    it 'ticks it off short of the file\'s own mark, where the channel ends it' do
      channel.update!(skip_credits_seconds: 600)

      post progress_entry_path(entry, channel: channel.id), params: { progress: 5_200 }

      expect(user.user_entry_for(entry)).to be_completed
    end

    it 'leaves the file\'s own mark alone on a channel that skips nothing' do
      post progress_entry_path(entry, channel: channel.id), params: { progress: 5_200 }

      expect(user.user_entry_for(entry)).not_to be_completed
    end

    # watching_channel refuses a channel that does not hold the entry, so a hand-edited id
    # cannot borrow another channel's skip to tick things off early.
    it 'ignores the skip of a channel the entry is not on' do
      elsewhere = create(:list, user: user, skip_credits_seconds: 600)

      post progress_entry_path(entry, channel: elsewhere.id), params: { progress: 5_200 }

      expect(user.user_entry_for(entry)).not_to be_completed
    end

    it 'ignores credits longer than the entry itself' do
      channel.update!(skip_credits_seconds: 7_000)

      post progress_entry_path(entry, channel: channel.id), params: { progress: 5_200 }

      expect(user.user_entry_for(entry)).not_to be_completed
    end
  end

  describe 'where it picks up next time' do
    before { sign_in user }

    # Somebody the channel moved on at 5,200 is past its end, and should not reopen there.
    it 'starts over rather than resuming past where the channel ends it' do
      user.user_entry_for!(entry).record_progress!(5_200)
      channel.update!(skip_credits_seconds: 600)

      get watch_entry_path(entry)

      expect(response.body).not_to include('startAt')
    end

    it 'still resumes there on a channel that plays to the end' do
      user.user_entry_for!(entry).record_progress!(5_200)

      get watch_entry_path(entry)

      expect(response.body).to include('startAt=5200')
    end

    # A two-minute clip with a minute of credits counts as watched at 57 seconds, so an
    # intro skip of 58 would open it already watched.
    it 'holds the intro skip under the shortened mark' do
      short = create(:entry, list: channel, media: 'movie', name: 'A Short', imdb: 'tt0000001', length: 2)
      channel.update!(skip_intro_seconds: 58)

      get watch_entry_path(short)
      expect(response.body).to include('startAt=58')

      channel.update!(skip_credits_seconds: 60)

      get watch_entry_path(short)
      expect(response.body).not_to include('startAt')
    end
  end
end
