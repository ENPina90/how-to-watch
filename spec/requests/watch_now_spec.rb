require 'rails_helper'

RSpec.describe 'watch_now', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it 'renders a movie without touching TMDB' do
    get watch_now_path(imdb: 'tt0848228', title: 'The Avengers', type: 'movie')

    expect(response).to be_successful
  end

  it 'still renders a show when TMDB is unreachable' do
    allow_any_instance_of(TmdbService).to receive(:fetch_show).and_raise(TmdbService::RequestError, 'timeout')
    allow_any_instance_of(TmdbService).to receive(:find_by_imdb_id).and_raise(TmdbService::RequestError, 'timeout')

    get watch_now_path(imdb: 'tt0903747', title: 'Breaking Bad', type: 'tv', tmdb: '1396')

    expect(response).to be_successful
  end

  it 'rejects a malformed imdb id' do
    get watch_now_path(imdb: 'not-an-id', title: 'Nope', type: 'movie')

    expect(response).to redirect_to(root_path)
  end
end
