# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'The profile page', type: :request do
  let(:user) { create(:user, username: 'nic') }
  let(:body) { Rails.root.join('spec/fixtures/letterboxd/diary.xml').read }

  before do
    sign_in user
    stub_request(:get, %r{letterboxd\.com/.+/rss/}).to_return(status: 200, body: body)
    stub_request(:get, %r{api\.themoviedb\.org}).to_return(status: 200, body: { imdb_id: 'tt1' }.to_json)
  end

  it 'is reachable from the name in the navbar' do
    get root_path

    expect(response.body).to include(profile_path)
  end

  it 'needs an account' do
    sign_out user
    get profile_path

    expect(response).to redirect_to(new_user_session_path)
  end

  describe 'the statistics' do
    it 'counts channels, entries, and what is left to watch' do
      channel = create(:list, user: user)
      watched = create(:entry, list: channel, name: 'Seen')
      create(:entry, list: channel, name: 'Unseen')
      user.mark_completed!(watched)

      get profile_path

      # The factory user already owns the default channel created on sign-up.
      expect(assigns(:lists_count)).to eq(2)
      expect(assigns(:entries_count)).to eq(2)
      expect(assigns(:unwatched_count)).to eq(1)
    end
  end

  describe 'reporting the sync' do
    let(:user) { create(:user, username: 'testmember', letterboxd_enabled: true) }

    # A channel that has not appeared yet looks exactly like one that failed, so the page
    # has to distinguish them.
    it 'says it is still working before the job has run' do
      get profile_path

      expect(response.body).to include('Reading your Letterboxd diary')
    end

    it 'shows the reason the diary could not be read' do
      user.update_columns(letterboxd_sync_error: 'Letterboxd feed for testmember returned 403')

      get profile_path

      expect(response.body).to include('Could not read your diary')
      expect(response.body).to include('returned 403')
    end

    it 'links to the channel once it exists' do
      LetterboxdSyncJob.perform_now(user.id)
      # The job writes through its own instance; Warden's test mode holds on to the one
      # signed in above, where a real request would reload it from the session.
      user.reload

      get profile_path

      expect(response.body).to include("Testmember&#39;s Letterbox")
      expect(response.body).to include('3 films')
    end

    it 'offers a manual sync, for when the queue has not run one' do
      expect { post letterboxd_sync_path }.to have_enqueued_job(LetterboxdSyncJob).with(user.id)
      expect(response).to redirect_to(profile_path)
    end

    it 'refuses a manual sync with no username to read' do
      user.update_columns(username: nil, letterboxd_enabled: true)

      expect { post letterboxd_sync_path }.not_to have_enqueued_job(LetterboxdSyncJob)
      expect(flash[:alert]).to match(/username/i)
    end
  end

  describe 'deleting the account' do
    # `lists` has a foreign key, so without dependent: :destroy this raised
    # ActiveRecord::InvalidForeignKey and the button on this page simply errored.
    it 'takes the channels with it' do
      create(:list, user: user)

      expect { delete user_registration_path }.to change { User.count }.by(-1)
      expect(List.where(user_id: user.id)).to be_empty
    end
  end

  describe 'updating the profile' do
    it 'changes the username without asking for a password' do
      patch profile_path, params: { user: { username: 'newname' } }

      expect(response).to redirect_to(profile_path)
      expect(user.reload.username).to eq('newname')
    end

    it 'turns the Letterboxd link on' do
      patch profile_path, params: { user: { username: 'testmember', letterboxd_enabled: '1' } }

      expect(user.reload).to be_letterboxd_enabled
    end

    it 'turns it off again, taking the channel with it' do
      user.update!(username: 'testmember', letterboxd_enabled: true)
      LetterboxdList.new(user).sync!

      patch profile_path, params: { user: { username: 'testmember', letterboxd_enabled: '0' } }

      expect(user.reload).not_to be_letterboxd_enabled
      expect(user.lists.where(letterboxd: true)).not_to exist
    end

    it 're-renders with the error when the change is refused' do
      patch profile_path, params: { user: { username: '', letterboxd_enabled: '1' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('needed to link a Letterboxd account')
    end

    # Devise's default lands at the site root, which reads as having been logged out.
    it 'comes back to the profile after changing the password' do
      put user_registration_path, params: {
        user: { email: user.email, password: '', password_confirmation: '',
                current_password: 'password', username: 'nic' }
      }

      expect(response).to redirect_to(profile_path)
    end

    # Email and password are Devise's, and it asks for the current password.
    it 'does not let the profile form change the email' do
      patch profile_path, params: { user: { username: 'nic', email: 'attacker@example.com' } }

      expect(user.reload.email).not_to eq('attacker@example.com')
    end
  end
end
