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

    # Email and password are Devise's, and it asks for the current password.
    it 'does not let the profile form change the email' do
      patch profile_path, params: { user: { username: 'nic', email: 'attacker@example.com' } }

      expect(user.reload.email).not_to eq('attacker@example.com')
    end
  end
end
