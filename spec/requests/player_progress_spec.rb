# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Player progress', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list, media: 'movie', imdb: 'tt0111161', length: 100) }

  describe 'recording where the player reached' do
    before { sign_in user }

    it 'saves the position against this member and entry' do
      post progress_entry_path(entry), params: { progress: 742.5 }

      expect(response).to have_http_status(:no_content)
      expect(user.user_entry_for(entry).player_progress).to eq(742.5)
    end

    # The page that asks is usually already unloading, so there is nothing to send back.
    it 'answers with nothing at all' do
      post progress_entry_path(entry), params: { progress: 10 }

      expect(response.body).to be_empty
    end

    it 'starts tracking an entry this member has never touched' do
      expect { post progress_entry_path(entry), params: { progress: 10 } }
        .to change { UserEntry.where(user: user, entry: entry).count }.from(0).to(1)
    end

    it 'ticks the film off once the position is far enough through' do
      post progress_entry_path(entry), params: { progress: 5_700 }

      expect(user.user_entry_for(entry)).to be_completed
    end

    it 'ticks the film off when the player reports it finished' do
      post progress_entry_path(entry), params: { progress: 120, finished: 'true' }

      expect(user.user_entry_for(entry)).to be_completed
    end

    it 'leaves a film stopped part way through unwatched' do
      post progress_entry_path(entry), params: { progress: 600 }

      expect(user.user_entry_for(entry)).not_to be_completed
    end
  end

  # A write like any other: guests never get through, so a session that lapsed mid-film
  # records nothing rather than writing against whoever comes next.
  it 'records nothing for a signed-out viewer' do
    post progress_entry_path(entry), params: { progress: 742.5 }

    expect(response).to redirect_to(new_user_session_path)
    expect(UserEntry.count).to eq(0)
  end

end
