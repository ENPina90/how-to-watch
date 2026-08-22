require 'rails_helper'

RSpec.describe 'Letterboxd bulk sync', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it 'enqueues the sync instead of running it in the request' do
    allow_any_instance_of(User).to receive(:letterboxd_connected?).and_return(true)

    expect {
      post bulk_sync_to_letterboxd_path
    }.to have_enqueued_job(LetterboxdBulkSyncJob).with(user.id)

    expect(response).to redirect_to(edit_user_registration_path)
  end

  it 'tells an unconnected user to connect first' do
    allow_any_instance_of(User).to receive(:letterboxd_connected?).and_return(false)

    expect {
      post bulk_sync_to_letterboxd_path
    }.not_to have_enqueued_job(LetterboxdBulkSyncJob)

    expect(flash[:alert]).to match(/connect to Letterboxd/i)
  end
end
