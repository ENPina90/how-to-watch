require 'rails_helper'

# `can_edit_list?` has always let an admin write to any channel, but every place that offers
# a channel to file an entry into was built from the member's own `lists`. So an admin could
# open somebody else's channel and edit it, yet not add a search result to it, move an entry
# into it, or see it in a picker. `User#editable_lists` is the one answer they all ask now.
RSpec.describe 'An admin on any channel', type: :request do
  let(:admin)    { create(:user, :admin) }
  let(:member)   { create(:user) }
  let(:stranger) { create(:user) }
  let!(:theirs)  { create(:list, user: stranger, name: 'Somebody Elses Westerns', private: false) }

  def created
    { status: :created, message: 'added', entry: create(:entry, list: theirs, name: 'Added') }
  end

  describe 'adding a search result' do
    it 'files it into a channel the admin does not own' do
      sign_in admin
      importer = instance_double(ImdbEntryImporter, call: created)
      expect(ImdbEntryImporter).to receive(:new).with(hash_including(list: theirs)).and_return(importer)

      post '/lists/add_to_list', params: { list_id: theirs.id, imdb: 'tt0000000' }

      expect(response).to have_http_status(:ok)
    end

    it 'still refuses a member somebody else\'s channel' do
      sign_in member
      expect(ImdbEntryImporter).not_to receive(:new)

      post '/lists/add_to_list', params: { list_id: theirs.id, imdb: 'tt0000000' }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the search overlay\'s channel picker' do
    def picker_ids
      raw = Nokogiri::HTML(response.body).at_css('[data-list-search-user-lists-value]')['data-list-search-user-lists-value']
      JSON.parse(raw).map { |list| list['id'] }
    end

    it 'offers an admin every channel' do
      sign_in admin
      get list_path(theirs)

      expect(picker_ids).to include(theirs.id)
    end

    it 'offers a member only their own' do
      sign_in member
      get list_path(theirs)

      expect(picker_ids).not_to include(theirs.id)
    end
  end

  describe 'moving an entry' do
    let(:own_list) { create(:list, user: admin, name: 'Admin Own') }
    let(:entry)    { create(:entry, list: own_list, name: 'Mover', media: 'movie', imdb: 'tt1', position: 1) }

    it 'lists somebody else\'s channel in the edit form\'s Channel select' do
      sign_in admin
      get edit_entry_path(entry)

      options = Nokogiri::HTML(response.body).css('select[name="entry[list_id]"] option').map { |o| o['value'].to_i }
      expect(options).to include(theirs.id, own_list.id)
    end

    # The standalone edit page named its select `entry[list]`, which `entry_params` does not
    # permit, so picking another channel there saved and silently left the entry where it was.
    it 'moves the entry into somebody else\'s channel from that form' do
      sign_in admin
      patch entry_path(entry), params: { entry: { list_id: theirs.id } }

      expect(entry.reload.list).to eq(theirs)
    end
  end

  describe 'adding a channel to a channel' do
    let(:child) { create(:list, user: create(:user), name: 'Spaghetti Westerns') }

    it 'files any channel into somebody else\'s for an admin' do
      sign_in admin
      patch list_move_to_list_path(child), params: { target_list_id: theirs.id }

      expect(theirs.reload.child_lists).to include(child)
    end

    it 'still refuses a member' do
      sign_in member
      patch list_move_to_list_path(child), params: { target_list_id: theirs.id }

      expect(theirs.reload.child_lists).not_to include(child)
    end
  end
end
