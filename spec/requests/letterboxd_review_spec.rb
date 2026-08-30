# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Opening a review on Letterboxd', type: :request do
  let(:user) { create(:user, username: 'testmember', letterboxd_enabled: true) }
  let(:list) { create(:list, user: user) }
  let(:body) { Rails.root.join('spec/fixtures/letterboxd/diary.xml').read }

  before do
    stub_request(:get, %r{letterboxd\.com/.+/rss/}).to_return(status: 200, body: body)
    stub_request(:get, %r{api\.themoviedb\.org}).to_return(status: 200, body: { imdb_id: 'tt1' }.to_json)
    sign_in user
  end

  # Only the canonical /film/<slug>/ accepts a trailing /review/. The /imdb/<id>/ shortcut
  # redirects the film, not a path hanging off it, so /imdb/<id>/review/ is a dead URL.
  it 'sends a film with a known slug straight to its review prompt' do
    entry = create(:entry, list: list, media: 'movie', letterboxd_slug: 'crime-101')

    get letterboxd_review_path(entry)

    expect(response).to redirect_to('https://letterboxd.com/film/crime-101/review/')
  end

  it 'resolves the slug from the IMDb shortcut and keeps it' do
    entry = create(:entry, list: list, media: 'movie', imdb: 'tt0010323', letterboxd_slug: nil)
    stub_request(:get, 'https://letterboxd.com/imdb/tt0010323/')
      .to_return(status: 302, headers: { 'Location' => 'https://letterboxd.com/film/the-cabinet-of-dr-caligari-1920/' })

    get letterboxd_review_path(entry)

    expect(response).to redirect_to('https://letterboxd.com/film/the-cabinet-of-dr-caligari-1920/review/')
    expect(entry.reload.letterboxd_slug).to eq('the-cabinet-of-dr-caligari-1920')
  end

  it 'does not resolve the same film twice' do
    entry = create(:entry, list: list, media: 'movie', imdb: 'tt0010323', letterboxd_slug: nil)
    stub = stub_request(:get, 'https://letterboxd.com/imdb/tt0010323/')
           .to_return(status: 302, headers: { 'Location' => 'https://letterboxd.com/film/caligari/' })

    2.times { get letterboxd_review_path(entry) }

    expect(stub).to have_been_made.once
  end

  # One further click to the same place beats a dead link.
  it 'falls back to the film page when the slug cannot be resolved' do
    entry = create(:entry, list: list, media: 'movie', imdb: 'tt0010323', letterboxd_slug: nil)
    stub_request(:get, 'https://letterboxd.com/imdb/tt0010323/').to_timeout

    get letterboxd_review_path(entry)

    expect(response).to redirect_to('https://letterboxd.com/imdb/tt0010323/')
  end

  it 'falls back to the TMDB shortcut for a film with no IMDb id' do
    entry = create(:entry, list: list, media: 'movie', imdb: nil, tmdb: '278', letterboxd_slug: nil)
    stub_request(:get, 'https://letterboxd.com/tmdb/278/').to_return(status: 404)

    get letterboxd_review_path(entry)

    expect(response).to redirect_to('https://letterboxd.com/tmdb/278/')
  end

  describe 'the refresh it books' do
    let(:entry) { create(:entry, list: list, media: 'movie', letterboxd_slug: 'crime-101') }

    it 'waits for the review to reach the feed rather than syncing now' do
      expect { get letterboxd_review_path(entry) }
        .to have_enqueued_job(LetterboxdSyncJob)
        .with(user.id)
        .at(a_value_within(1.minute).of(LetterboxdController::REVIEW_DELAY.from_now))
    end

    it 'books one refresh however many films are opened' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

      expect { 3.times { get letterboxd_review_path(entry) } }
        .to have_enqueued_job(LetterboxdSyncJob).exactly(:once)
    end

    it 'books nothing for a member with no linked diary' do
      sign_in create(:user, username: 'unlinked')

      expect { get letterboxd_review_path(entry) }.not_to have_enqueued_job(LetterboxdSyncJob)
      expect(response).to have_http_status(:redirect)
    end
  end
end
