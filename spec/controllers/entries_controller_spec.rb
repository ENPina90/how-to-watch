# spec/controllers/entries_controller_spec.rb
require 'rails_helper'

RSpec.describe EntriesController, type: :controller do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list) }
  let(:valid_attributes) { attributes_for(:entry, list: list) }
  let(:invalid_attributes) { { name: nil } }

  before do
    sign_in user
  end

  describe "GET #new" do
    it "returns a success response" do
      get :new, params: { list_id: list.id }
      expect(response).to be_successful
    end
  end

  describe "GET #show" do
    it "returns a success response" do
      get :show, params: { id: entry.to_param }
      expect(response).to be_successful
    end
  end

  describe "POST #create" do
    context "with valid params" do
      before do
        allow(OmdbApi).to receive(:get_movie).and_return({
          "Type" => "movie",
          "imdbID" => "tt1234567",
          "Title" => "Test Movie",
          "Runtime" => "120 min",
          "Genre" => "Action",
          "Director" => "John Doe",
          "Writer" => "Jane Doe",
          "Actors" => "Actor 1, Actor 2",
          "Plot" => "A test plot.",
          "imdbRating" => "7.5",
          "Year" => "2021"
        })
      end

      it "creates a new Entry" do
        expect {
          post :create, params: { list_id: list.id, imdb: "tt1234567" }
        }.to change(Entry, :count).by(1)
      end

      it "redirects to the edit page of the created entry" do
        post :create, params: { list_id: list.id, imdb: "tt1234567" }
        expect(response).to redirect_to(edit_entry_path(Entry.last))
      end
    end

    context "with invalid params" do
      it "renders the 'new' template" do
        post :create, params: { list_id: list.id, entry: invalid_attributes }
        expect(response).to render_template("new")
      end
    end
  end

  describe "GET #edit" do
    it "returns a success response" do
      get :edit, params: { id: entry.to_param }
      expect(response).to be_successful
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) { { name: "New Name", list_id: list.id } }

      it "updates the requested entry" do
        put :update, params: { id: entry.to_param, entry: new_attributes }
        entry.reload
        expect(entry.name).to eq("New Name")
      end

      it "redirects to the list page" do
        put :update, params: { id: entry.to_param, entry: new_attributes }
        expect(response).to redirect_to(list_path(list, anchor: entry.imdb))
      end
    end

    context "with invalid params" do
      it "renders the 'edit' template" do
        put :update, params: { id: entry.to_param, entry: invalid_attributes }
        expect(response).to render_template("edit")
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested entry" do
      entry_to_destroy = create(:entry, list: list)
      expect {
        delete :destroy, params: { id: entry_to_destroy.to_param }
      }.to change(Entry, :count).by(-1)
    end

    it "redirects to the list page" do
      delete :destroy, params: { id: entry.to_param }
      expect(response).to redirect_to(list_path(list))
    end
  end

  describe "POST #duplicate" do
    it "duplicates the entry" do
      post :duplicate, params: { id: entry.to_param }
      expect(Entry.count).to eq(2)
    end

    it "redirects to the edit page of the duplicated entry" do
      post :duplicate, params: { id: entry.to_param }
      expect(response).to redirect_to(edit_entry_path(Entry.last))
    end
  end

  describe "GET #watch" do
    it "renders the special layout" do
      get :watch, params: { id: entry.to_param }
      expect(response).to render_template(layout: "special_layout")
    end
  end

  describe "POST #complete" do
    it "toggles the completed attribute" do
      post :complete, params: { id: entry.to_param }
      entry.reload
      expect(entry.completed).to be_truthy
      post :complete, params: { id: entry.to_param }
      entry.reload
      expect(entry.completed).to be_falsey
    end
  end

  describe "POST #reportlink" do
    it "toggles the stream attribute" do
      post :reportlink, params: { id: entry.to_param }
      entry.reload
      expect(entry.stream).to be_truthy
      post :reportlink, params: { id: entry.to_param }
      entry.reload
      expect(entry.stream).to be_falsey
    end
  end
end
