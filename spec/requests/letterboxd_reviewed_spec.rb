# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Refreshing after a review', type: :request do
  let(:user) { create(:user, username: 'testmember', letterboxd_enabled: true) }
  let(:body) { Rails.root.join('spec/fixtures/letterboxd/diary.xml').read }

  before do
    stub_request(:get, %r{letterboxd\.com/.+/rss/}).to_return(status: 200, body: body)
    stub_request(:get, %r{api\.themoviedb\.org}).to_return(status: 200, body: { imdb_id: 'tt1' }.to_json)
  end

  # A review posted on Letterboxd is not in the feed straight away, so the refresh waits
  # for it rather than reading a diary that cannot have caught up yet.
  it 'books a refresh for later rather than syncing now' do
    sign_in user

    expect { post letterboxd_reviewed_path }
      .to have_enqueued_job(LetterboxdSyncJob)
      .with(user.id)
      .at(a_value_within(1.minute).of(LetterboxdController::REVIEW_DELAY.from_now))

    expect(response).to have_http_status(:accepted)
  end

  it 'ignores a member who has not linked an account' do
    sign_in create(:user, username: 'unlinked')

    expect { post letterboxd_reviewed_path }.not_to have_enqueued_job(LetterboxdSyncJob)
    expect(response).to have_http_status(:no_content)
  end

  it 'turns a signed-out visitor away' do
    post letterboxd_reviewed_path

    expect(response).to redirect_to(new_user_session_path)
  end

  # Working through several films should book one diary read, not one per click.
  it 'books only one refresh while another is still pending' do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    sign_in user

    expect {
      3.times { post letterboxd_reviewed_path }
    }.to have_enqueued_job(LetterboxdSyncJob).exactly(:once)
  end

  describe 'the button that triggers it' do
    let(:list) { create(:list, user: user) }

    it 'pings the server for a linked member' do
      create(:entry, list: list, media: 'movie', imdb: 'tt0111161')
      sign_in user

      get list_path(list)

      expect(response.body).to include('letterboxd-review')
      expect(response.body).to include(letterboxd_reviewed_path)
    end

    it 'is a plain link for someone with no diary to refresh' do
      unlinked = create(:user, username: 'unlinked')
      other_list = create(:list, user: unlinked)
      create(:entry, list: other_list, media: 'movie', imdb: 'tt0111161')
      sign_in unlinked

      get list_path(other_list)

      expect(response.body).to include('fa-square-letterboxd')
      expect(response.body).not_to include('letterboxd-review')
    end
  end
end
