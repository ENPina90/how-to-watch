# frozen_string_literal: true

require 'rails_helper'

# Landing part-way into something, the way a channel is already halfway through a film when
# you flip onto it.
RSpec.describe 'Starting part-way in', type: :request do
  let(:user) { create(:user) }
  let(:channel) { create(:list, user: user) }

  # Only a provider whose player takes a position carries one in its URL at all
  # (Source::RESUME_PARAMS), and the slug is what maps a provider to its player. Active and
  # first, so every entry here resolves to it without being told.
  let!(:provider) do
    Source.create!(name: 'Vidsrc2', slug: 'vidsrc2', kind: 'imdb', active: true, position: 1,
                   templates: { 'movie' => 'https://vidsrc2.ru/embed/movie?imdb=%{imdb}' })
  end

  # 100 minutes, so the runtime cap is nowhere near a three-minute window.
  let(:entry) { create(:entry, list: channel, media: 'movie', imdb: 'tt0111161', length: 100) }

  # The player takes whole seconds, so that is what ends up in the URL.
  def start_at
    response.body[/startAt=(\d+)/, 1]&.to_i
  end

  describe 'the setting' do
    before { sign_in user }

    it 'is off until somebody asks for it' do
      expect(user.randomizer).to eq(0)
    end

    it 'is offered on the profile' do
      get profile_path

      expect(response.body).to include('Start part-way in')
    end

    it 'records an answer' do
      patch profile_path, params: { user: { randomizer: '3.5' } }

      expect(user.reload.randomizer).to eq(3.5)
    end

    # Minutes before the start are not a thing.
    it 'refuses a negative window' do
      patch profile_path, params: { user: { randomizer: '-2' } }

      expect(user.reload.randomizer).to eq(0)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'what the player is given' do
    before { sign_in user }

    it 'starts at the beginning while the setting is off' do
      get watch_entry_path(entry)

      expect(response.body).not_to include('startAt')
    end

    it 'starts somewhere inside the window once it is on' do
      user.update!(randomizer: 3.5)

      get watch_entry_path(entry)

      expect(start_at).to be_between(0, 3.5 * 60).inclusive
    end

    # The whole point of it: flipping back should not land in the same place.
    it 'picks a fresh spot every time' do
      user.update!(randomizer: 30)

      spots = Array.new(8) do
        get watch_entry_path(entry)
        start_at
      end

      expect(spots.uniq.length).to be > 1
    end

    # Picking up where you left off is something the viewer asked for; this is not.
    it 'gives way to a position the viewer already left off at' do
      user.update!(randomizer: 3.5)
      user.user_entry_for!(entry).record_progress!(2_400)

      get watch_entry_path(entry)

      expect(start_at).to eq(2_400)
    end

    it 'applies again once a finished entry starts over' do
      user.update!(randomizer: 3.5)
      # Past the completion mark, so there is no position worth resuming.
      user.user_entry_for!(entry).record_progress!(5_900)

      get watch_entry_path(entry)

      expect(start_at).to be_between(0, 3.5 * 60).inclusive
    end

    # A three-minute window over a two-minute cartoon would open it in its own credits --
    # past the mark where it counts as watched, so it would be marked seen unwatched.
    it 'will not drop the viewer past the point an entry counts as watched' do
      user.update!(randomizer: 30)
      short = create(:entry, list: channel, media: 'movie', name: 'A Short', imdb: 'tt0000001', length: 2)

      25.times do
        get watch_entry_path(short)
        expect(start_at.to_i).to be < 2 * 60 * UserEntry::COMPLETION_FRACTION
      end
    end

    it 'leaves an entry with no runtime to the window alone' do
      user.update!(randomizer: 1)
      unknown = create(:entry, list: channel, media: 'movie', name: 'No Runtime', imdb: 'tt0000002', length: nil)

      get watch_entry_path(unknown)

      expect(start_at).to be_between(0, 60).inclusive
    end
  end

  # Nobody to have a setting, so nothing changes for them.
  it 'starts a signed-out viewer at the beginning' do
    AppSetting.update_access_mode!('open')

    get watch_entry_path(entry)

    expect(response.body).not_to include('startAt')
  end
end
