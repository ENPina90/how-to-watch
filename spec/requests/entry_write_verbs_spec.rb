require 'rails_helper'

# CSRF tokens do not protect GET, so an <img src>, a link prefetch or a crawler hitting a
# GET route that writes could change a user's data. These specs pin the verbs: the write
# must work, and the GET must not exist.
RSpec.describe 'Entry write verbs', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list) }

  before { sign_in user }

  describe 'marking an entry complete' do
    it 'toggles completion over PATCH' do
      patch complete_entry_path(entry)
      expect(entry.completed_by?(user)).to be true
    end

    it 'is not reachable over GET' do
      get "/entries/#{entry.id}/complete"

      expect(response).to have_http_status(:not_found)
      expect(entry.reload.completed_by?(user)).to be false
    end
  end

  describe 'reporting a broken link' do
    it 'toggles the stream flag over PATCH' do
      entry.update!(stream: false)

      patch reportlink_entry_path(entry)

      expect(entry.reload.stream).to be true
    end

    it 'is not reachable over GET' do
      entry.update!(stream: false)

      get "/entries/#{entry.id}/reportlink"

      expect(response).to have_http_status(:not_found)
      expect(entry.reload.stream).to be false
    end
  end

  describe 'duplicating an entry' do
    it 'creates a copy over POST' do
      entry_to_copy = entry

      expect {
        post duplicate_entry_path(entry_to_copy)
      }.to change(Entry, :count).by(1)
    end

    it 'is not reachable over GET' do
      entry_to_copy = entry

      expect {
        get "/entries/#{entry_to_copy.id}/duplicate"
      }.not_to change(Entry, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'poster maintenance actions' do
    it 'exposes repair_image and migrate_poster over PATCH only' do
      get "/entries/#{entry.id}/repair_image"
      expect(response).to have_http_status(:not_found)

      get "/entries/#{entry.id}/migrate_poster"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'reads that must stay GET' do
    it 'still serves the watch page, even with no sibling list to flip to' do
      get watch_entry_path(entry)
      expect(response).to be_successful
    end

    it 'still serves the poster lookup' do
      # An entry with no external ids, so this stays a check on the verb rather than on
      # TMDB/OMDB (PosterCandidates has its own specs).
      idless = create(:entry, list: list, name: 'No ids', position: 2,
                              imdb: nil, tmdb: nil, series_imdb: nil)

      get fetch_posters_entry_path(idless)

      expect(response).to be_successful
      expect(response.parsed_body['posters']).to eq([])
    end
  end
end
