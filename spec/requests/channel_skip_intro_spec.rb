# frozen_string_literal: true

require 'rails_helper'

# A channel that knows where its programmes begin, opening every entry there. The other way
# round from the playback preferences: the channel overrides the member's "Start part-way
# in", because a random point inside the titles is not a better answer to where a
# programme starts.
RSpec.describe 'Skipping a channel intro', type: :request do
  let(:user) { create(:user) }
  let(:channel) { create(:list, user: user) }

  # Only a provider whose player takes a position carries one in its URL at all
  # (Source::RESUME_PARAMS). Active and first, so every entry resolves to it unasked.
  let!(:provider) do
    Source.create!(name: 'Vidsrc2', slug: 'vidsrc2', kind: 'imdb', active: true, position: 1,
                   templates: { 'movie' => 'https://vidsrc2.ru/embed/movie?imdb=%{imdb}' })
  end

  let(:entry) { create(:entry, list: channel, media: 'movie', imdb: 'tt0111161', length: 100) }

  def start_at
    response.body[/startAt=(\d+)/, 1]&.to_i
  end

  describe 'the setting' do
    before { sign_in user }

    it 'is blank until somebody sets it' do
      expect(channel.skip_intro_seconds).to be_nil
    end

    it 'is offered on the channel edit form' do
      get edit_list_path(channel)

      expect(response.body).to include('name="list[skip_intro_seconds]"')
      expect(response.body).to include('Skip intro')
    end

    it 'records an answer' do
      patch list_path(channel), params: { list: { skip_intro_seconds: '90' } }

      expect(channel.reload.skip_intro_seconds).to eq(90)
    end

    # Blank is "no opinion", which is not the same answer as zero.
    it 'takes a cleared field as no opinion rather than zero' do
      channel.update!(skip_intro_seconds: 90)

      patch list_path(channel), params: { list: { skip_intro_seconds: '' } }

      expect(channel.reload.skip_intro_seconds).to be_nil
    end

    it 'refuses a point before the start' do
      patch list_path(channel), params: { list: { skip_intro_seconds: '-5' } }

      expect(channel.reload.skip_intro_seconds).to be_nil
    end
  end

  describe 'what the player is given' do
    before { sign_in user }

    it 'opens the entry past the intro' do
      channel.update!(skip_intro_seconds: 90)

      get watch_entry_path(entry)

      expect(start_at).to eq(90)
    end

    it 'overrides the member starting part-way in' do
      user.update!(randomizer: 30)
      channel.update!(skip_intro_seconds: 90)

      4.times do
        get watch_entry_path(entry)
        expect(start_at).to eq(90)
      end
    end

    # Zero is an answer: always from the top, whatever the member asked for.
    it 'starts at the beginning when the channel says zero, randomiser or not' do
      user.update!(randomizer: 30)
      channel.update!(skip_intro_seconds: 0)

      get watch_entry_path(entry)

      expect(response.body).not_to include('startAt')
    end

    # `start_at` is nil when the URL carries no position at all, and that is one of the
    # answers this example is testing for rather than a failure: User#random_start_for
    # floors its roll to whole seconds, so anything under a second becomes 0, and
    # Source#append_resume leaves a zero out of the URL entirely. Asserting on the figure
    # alone failed about one run in two hundred, on master and here alike.
    it 'leaves the member to their own setting while the channel has no opinion' do
      user.update!(randomizer: 3.5)

      get watch_entry_path(entry)

      expect(start_at || 0).to be_between(0, 3.5 * 60).inclusive
    end

    # Picking up where you left off is something the viewer asked for.
    it 'gives way to a position the viewer already left off at' do
      channel.update!(skip_intro_seconds: 90)
      user.user_entry_for!(entry).record_progress!(2_400)

      get watch_entry_path(entry)

      expect(start_at).to eq(2_400)
    end

    # Ninety seconds into a one-minute clip is past the point it counts as watched.
    it 'starts something too short for it at the beginning' do
      channel.update!(skip_intro_seconds: 90)
      short = create(:entry, list: channel, media: 'movie', name: 'A Short', imdb: 'tt0000001', length: 1)

      get watch_entry_path(short)

      expect(response.body).not_to include('startAt')
    end

    # The channel watched from decides, not the one the entry happens to live in.
    it 'follows the channel being watched from' do
      parent = create(:list, user: user, skip_intro_seconds: 45)
      parent.child_lists << channel
      channel.update!(skip_intro_seconds: 90)

      get watch_entry_path(entry, channel: parent.id)

      expect(start_at).to eq(45)
    end
  end

  # The channel's word is about the programme, not about a person, so it holds for anyone.
  it 'skips the intro for a signed-out viewer too' do
    AppSetting.update_access_mode!('open')
    channel.update!(skip_intro_seconds: 90)

    get watch_entry_path(entry)

    expect(start_at).to eq(90)
  end
end
