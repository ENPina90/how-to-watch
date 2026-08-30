# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'The Letterboxd button', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  describe 'on a movie card' do
    it 'links to the film with the review prompt open' do
      create(:entry, list: list, media: 'movie', imdb: 'tt0111161')

      get list_path(list)

      expect(response.body).to include('https://letterboxd.com/imdb/tt0111161/review/')
      expect(response.body).to include('fa-square-letterboxd')
    end

    # Only diary imports carry an IMDb id; a film matched from the feed has a TMDB id
    # until the backfill runs, and the link has to work in the meantime.
    it 'falls back to the TMDB id when there is no IMDb id' do
      create(:entry, list: list, media: 'movie', imdb: nil, tmdb: '278')

      get list_path(list)

      expect(response.body).to include('https://letterboxd.com/tmdb/278/review/')
    end

    it 'is left off a movie with no id to resolve the film by' do
      create(:entry, list: list, media: 'movie', imdb: nil, tmdb: nil)

      get list_path(list)

      expect(response.body).not_to include('fa-square-letterboxd')
    end

    # Letterboxd catalogues films only.
    it 'is left off anything that is not a movie' do
      create(:entry, list: list, media: 'series', name: 'Some Show', imdb: 'tt0903747')

      get list_path(list)

      expect(response.body).not_to include('fa-square-letterboxd')
    end
  end

  describe 'on the watch page' do
    it 'rides the source switcher line for a movie', :needs_provider do
      entry = create(:entry, list: list, media: 'movie', imdb: 'tt0111161')

      get watch_entry_path(entry)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('watch-letterboxd')
      expect(response.body).to include('https://letterboxd.com/imdb/tt0111161/review/')
    end

    it 'is absent for a series', :needs_provider do
      entry = create(:entry, list: list, media: 'series', name: 'A Show',
                             imdb: 'tt0903747', series_imdb: 'tt0903747')

      get watch_entry_path(entry)

      expect(response.body).not_to include('fa-square-letterboxd')
    end
  end

  describe 'the score on a card' do
    it 'is shown as half stars when the entry has one' do
      create(:entry, list: list, media: 'movie', letterboxd_score: 3.5)

      get list_path(list)

      expect(response.body).to include('letterboxd-score')
      expect(response.body).to include('fa-star-half-stroke')
    end

    it 'is left off entirely when the entry has no score' do
      create(:entry, list: list, media: 'movie', letterboxd_score: nil)

      get list_path(list)

      expect(response.body).not_to include('letterboxd-score')
    end
  end
end
