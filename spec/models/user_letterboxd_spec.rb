# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A user opting into Letterboxd', type: :model do
  let(:body) { Rails.root.join('spec/fixtures/letterboxd/diary.xml').read }

  before do
    stub_request(:get, %r{letterboxd\.com/.+/rss/}).to_return(status: 200, body: body)
    stub_request(:get, %r{api\.themoviedb\.org}).to_return(status: 200, body: { imdb_id: 'tt1' }.to_json)
    # Details are LetterboxdList's business; here it only matters that the sync survives
    # OMDb having nothing for the film.
    stub_request(:get, %r{omdbapi\.com}).to_return(status: 200, body: { Response: 'False' }.to_json)
  end

  it 'is refused without a username, which is the Letterboxd handle' do
    user = build(:user, username: nil, letterboxd_enabled: true)

    expect(user).not_to be_valid
    expect(user.errors[:username]).to include('is needed to link a Letterboxd account')
  end

  # The sync is an RSS fetch plus a TMDB lookup per new film, far too much to hold a
  # request open for.
  it 'syncs off the request when a new user opts in at sign-up' do
    expect { create(:user, username: 'testmember', letterboxd_enabled: true) }
      .to have_enqueued_job(LetterboxdSyncJob)
  end

  it 'syncs when an existing user ticks the box' do
    user = create(:user, username: 'testmember')

    expect { user.update!(letterboxd_enabled: true) }
      .to have_enqueued_job(LetterboxdSyncJob).with(user.id)
  end

  it 'does not sync for a user who never opted in' do
    expect { create(:user, username: 'testmember') }
      .not_to have_enqueued_job(LetterboxdSyncJob)
  end

  it 'deletes the channel when the box is unticked' do
    user = create(:user, username: 'testmember', letterboxd_enabled: true)
    LetterboxdList.new(user).sync!
    expect(user.lists.where(letterboxd: true)).to exist

    user.update!(letterboxd_enabled: false)

    expect(user.lists.where(letterboxd: true)).not_to exist
  end

  # The username is the handle, so changing it points at a different diary entirely.
  context 'when the username changes while linked' do
    let(:user) { create(:user, username: 'testmember', letterboxd_enabled: true) }

    before { LetterboxdList.new(user).sync! }

    it 're-syncs against the new handle' do
      expect { user.update!(username: 'someoneelse') }
        .to have_enqueued_job(LetterboxdSyncJob).with(user.id)
    end

    it 'renames the channel to match' do
      user.update!(username: 'someoneelse')

      expect(user.lists.find_by(letterboxd: true).name).to eq("Someoneelse's Letterbox")
    end
  end
end
