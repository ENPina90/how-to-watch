require 'rails_helper'

# increment/decrement/shuffle move the user's position, so they are writes even though
# they read like navigation.
RSpec.describe 'Entry navigation verbs', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, ordered: true) }
  let!(:first_entry)  { create(:entry, list: list, name: 'First',  position: 1) }
  let!(:second_entry) { create(:entry, list: list, name: 'Second', position: 2) }

  before { sign_in user }

  describe 'moving to the next entry' do
    it 'advances the user position over PATCH' do
      patch increment_current_entry_path(first_entry, mode: 'watch')

      expect(response).to redirect_to(watch_entry_path(second_entry))
    end

    it 'is not reachable over GET' do
      get "/entries/#{first_entry.id}/increment_current"

      expect(response).to have_http_status(:not_found)
      expect(list.position_for_user(user).current_position).to eq(1)
    end
  end

  describe 'moving to the previous entry' do
    it 'goes back over PATCH' do
      patch decrement_current_entry_path(second_entry, mode: 'watch')

      expect(response).to redirect_to(watch_entry_path(first_entry))
    end

    it 'is not reachable over GET' do
      get "/entries/#{second_entry.id}/decrement_current"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'shuffling' do
    it 'moves somewhere over PATCH' do
      patch shuffle_current_entry_path(first_entry, mode: 'watch')

      expect(response).to have_http_status(:redirect)
    end

    it 'is not reachable over GET' do
      get "/entries/#{first_entry.id}/shuffle_current"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the watch page controls' do
    it 'renders them as forms, since Turbo is disabled on that page' do
      get watch_entry_path(first_entry)

      expect(response).to be_successful
      expect(response.body).to include(increment_current_entry_path(first_entry, mode: 'watch'))
      # button_to emits a real form with a method override and an authenticity token
      expect(response.body).to include('name="_method" value="patch"')
    end
  end
end
