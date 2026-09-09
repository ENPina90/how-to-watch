# frozen_string_literal: true

require 'rails_helper'

# `entries.length` is the catalogue's claim about how long something runs, and for a good
# few entries there is no claim at all. The cable schedule falls back to a flat guess, and a
# guess that is short cuts a programme off partway through -- which is what happens to a
# 46-minute episode laid out in a 30-minute slot. Only the player knows what it is holding.
RSpec.describe 'Learning an entry\'s runtime', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:channel) { create(:list, user: user) }
  let(:entry) { create(:entry, list: channel, media: 'movie', imdb: 'tt0111161', length: nil) }

  describe 'when the catalogue says nothing' do
    before { sign_in user }

    it 'records what the player reports, to the nearest minute' do
      patch runtime_entry_path(entry), params: { seconds: 2748 }

      expect(response).to have_http_status(:no_content)
      expect(entry.reload.length).to eq(46)
    end

    it 'treats a zero-length entry as having said nothing' do
      entry.update!(length: 0)

      patch runtime_entry_path(entry), params: { seconds: 2748 }

      expect(entry.reload.length).to eq(46)
    end
  end

  # A runtime somebody set by hand, or one OMDB gave, is a considered value. Whichever cut a
  # provider happens to be serving today does not get to overrule it.
  it 'never overwrites a runtime the catalogue already has' do
    entry.update!(length: 142)
    sign_in user

    patch runtime_entry_path(entry), params: { seconds: 2748 }

    expect(entry.reload.length).to eq(142)
  end

  it 'ignores a report with no length in it' do
    sign_in user

    patch runtime_entry_path(entry), params: { seconds: 0 }

    expect(response).to have_http_status(:no_content)
    expect(entry.reload.length).to be_blank
  end

  # A show does not have a runtime -- its episodes do, and they do not agree with each
  # other. Writing what the player is holding onto the show would put one episode's length
  # on every other episode in the season.
  describe 'an episode of a series' do
    let(:series) { create(:entry, list: channel, media: 'series', imdb: 'tt0903747', length: nil) }
    let!(:episode) { Subentry.create!(entry: series, season: '1', episode: '1', name: 'Pilot') }

    before { sign_in user }

    it 'records the runtime against the episode that was playing' do
      patch runtime_entry_path(series), params: { seconds: 2748, subentry: episode.id }

      expect(episode.reload.length).to eq(46)
      expect(series.reload.length).to be_blank
    end

    it 'leaves an episode that already has one alone' do
      episode.update!(length: 22)

      patch runtime_entry_path(series), params: { seconds: 2748, subentry: episode.id }

      expect(episode.reload.length).to eq(22)
    end

    # An id from another entry, or one that has since been deleted. The show is what is
    # left, and it is the same answer as a report that named no episode at all.
    it 'falls back to the entry when the episode is not its own' do
      stranger = Subentry.create!(entry: create(:entry, list: channel, position: 2),
                                 season: '1', episode: '1', name: 'Elsewhere')

      patch runtime_entry_path(series), params: { seconds: 2748, subentry: stranger.id }

      expect(series.reload.length).to eq(46)
      expect(stranger.reload.length).to be_blank
    end
  end

  # Correcting the catalogue is a write, and writes need an account however open the site is.
  it 'refuses a visitor with no account' do
    AppSetting.update_access_mode!('open')

    patch runtime_entry_path(entry), params: { seconds: 2748 }

    expect(response).to redirect_to(new_user_session_path)
    expect(entry.reload.length).to be_blank
  end
end
