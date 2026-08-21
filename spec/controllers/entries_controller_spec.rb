require 'rails_helper'

RSpec.describe EntriesController, type: :controller do
  before do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @user = FactoryBot.create(:user)
    sign_in @user

    # Stub OMDB API request
    stub_request(:get, /www.omdbapi.com/)
      .to_return(status: 200, body: File.read(Rails.root.join('spec/fixtures/omdb_response.json')), headers: {})

    # Stub external URL request
    stub_request(:get, /https:\/\/v2\.vidsrc\.me\/embed\/tt0848228/)
      .to_return(status: 200, body: "", headers: {})
  end

  let(:list) { create(:list, user: @user) }
  let(:entry) { create(:entry, list: list) }

  describe 'GET #new' do
    it 'returns a success response' do
      get :new, params: { list_id: list.id }
      expect(response).to be_successful
    end
  end

  describe 'GET #show' do
    it 'returns a success response' do
      get :show, params: { id: entry.id }
      expect(response).to be_successful
    end
  end

  describe 'POST #create' do
    context 'with valid params' do
      it 'creates a new Entry' do
        expect {
          post :create, params: { list_id: list.id, imdb: 'tt0848228' }
        }.to change(Entry, :count).by(1)
      end

      it 'answers with the turbo streams that update the list in place' do
        post :create, params: { list_id: list.id, imdb: 'tt0848228' }
        expect(response).to be_successful
        expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
        expect(response.body).to include('entry_tt0848228_partial')
      end
    end

    context 'with invalid params' do
      before do
        allow(Entry).to receive(:create_from_source).and_return("Error")
      end

      it 'reports the problem in the flash stream' do
        post :create, params: { list_id: list.id, imdb: 'invalid_id' }
        expect(response).to render_template(partial: 'shared/_flashes')
        expect(flash.now[:alert]).to be_present
      end
    end
  end

  describe 'GET #edit' do
    it 'returns a success response' do
      get :edit, params: { id: entry.id }
      expect(response).to be_successful
    end
  end

  describe 'PATCH #update' do
    context 'with valid params' do
      let(:new_attributes) { { name: 'New Avengers', list: list.id } }

      it 'updates the requested entry' do
        patch :update, params: { id: entry.id, entry: new_attributes }
        entry.reload
        expect(entry.name).to eq('New Avengers')
      end

      it 'redirects to the list page' do
        patch :update, params: { id: entry.id, entry: new_attributes }
        expect(response).to redirect_to(list_path(entry.list, anchor: entry.imdb))
      end
    end

    context 'with invalid params' do
      let(:invalid_attributes) { { name: '', list: list.id } }

      it 'renders the edit template' do
        patch :update, params: { id: entry.id, entry: invalid_attributes }
        expect(response).to render_template(:edit)
      end
    end
  end

  describe 'POST #duplicate' do
    it 'duplicates the entry and redirects to the edit page' do
      entry_to_duplicate = entry
      expect {
        post :duplicate, params: { id: entry_to_duplicate.id }
      }.to change(Entry, :count).by(1)
      expect(response).to redirect_to(edit_entry_path(Entry.last))
    end
  end

  describe 'DELETE #destroy' do
    it 'destroys the requested entry' do
      entry_to_delete = create(:entry, list: list)
      expect {
        delete :destroy, params: { id: entry_to_delete.id }
      }.to change(Entry, :count).by(-1)
    end

    it 'redirects to the list page' do
      delete :destroy, params: { id: entry.id }
      expect(response).to redirect_to(list_path(list))
    end
  end

  describe 'GET #watch' do
    it 'returns a success response with special layout' do
      get :watch, params: { id: entry.id }
      expect(response).to be_successful
      expect(response).to render_template(layout: 'special_layout')
    end
  end

  describe 'PATCH #complete' do
    it 'toggles completion for the signed-in user' do
      patch :complete, params: { id: entry.id }
      expect(entry.completed_by?(@user)).to be_truthy

      # Toggling again removes the user's tracking entirely.
      patch :complete, params: { id: entry.id }
      expect(entry.reload.completed_by?(@user)).to be_falsey
    end

    it 'does not touch the legacy list-wide completed column' do
      patch :complete, params: { id: entry.id }
      expect(entry.reload.completed).to be_falsey
    end
  end

  describe 'PATCH #reportlink' do
    it 'toggles the stream attribute' do
      patch :reportlink, params: { id: entry.id }
      entry.reload
      expect(entry.stream).to be_truthy
      patch :reportlink, params: { id: entry.id }
      entry.reload
      expect(entry.stream).to be_falsey
    end
  end
end
