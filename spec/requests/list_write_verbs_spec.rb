require 'rails_helper'

RSpec.describe 'List write verbs', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  describe 'adding top episodes' do
    before do
      # The action scrapes IMDb and calls OMDB; neither belongs in a request spec.
      allow(TmdbService).to receive(:new).and_return(
        instance_double(TmdbService, fetch_imdb_id: 'tt0903747')
      )
      allow_any_instance_of(ImdbScraper).to receive(:fetch_episode_imdb_ids_with_ratings).and_return([])
    end

    it 'accepts POST' do
      post list_top_entries_path(list, tmdb: '1396', top_number: 5)

      expect(response).to redirect_to(list_path(list))
    end

    it 'is not reachable over GET' do
      get "/lists/#{list.id}/top_entries?tmdb=1396&top_number=5"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the removed randomize route' do
    it 'no longer resolves, since ListsController has no such action' do
      get "/lists/#{list.id}/randomize"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'reads that must stay GET' do
    it 'still resumes a list' do
      create(:entry, list: list, position: 1)

      get list_watch_current_path(list)

      expect(response).to have_http_status(:redirect)
    end
  end
end
