require 'rails_helper'

# check_edit_permissions guarded edit/update/destroy/update_poster, but several other
# actions write state shared by everyone who can see the entry and were reachable by any
# signed-in user: update_position reordered someone else's list, reportlink flipped the
# global `stream` flag, and set_source changed which provider served the entry.
RSpec.describe 'Entry authorization', :needs_provider, type: :request do
  let(:owner)     { create(:user) }
  let(:stranger)  { create(:user) }
  let(:list)      { create(:list, user: owner, default: false) }
  let(:entry)     { create(:entry, list: list, position: 1, media: 'movie', imdb: 'tt1', name: 'Owned') }

  describe 'a stranger' do
    before { sign_in stranger }

    it 'cannot reorder the list' do
      create(:entry, list: list, position: 2, name: 'Second')

      patch update_position_entry_path(entry), params: { position: 2 }

      expect(response).to have_http_status(:forbidden)
      expect(entry.reload.position).to eq(1)
    end

    it 'cannot flip the broken-link flag' do
      entry.update!(stream: false)

      patch reportlink_entry_path(entry)

      expect(response).to have_http_status(:forbidden)
      expect(entry.reload.stream).to be false
    end

    it 'cannot change which provider serves the entry' do
      other = Source.create!(name: 'Other', kind: 'imdb', active: true,
                             templates: { 'movie' => 'https://other.test/%{imdb}' })

      expect {
        patch set_source_entry_path(entry), params: { source_id: other.id }
      }.not_to change { entry.reload.provider_id }
    end

    it 'cannot replace the poster' do
      expect {
        patch repair_image_entry_path(entry)
        patch migrate_poster_entry_path(entry)
      }.not_to change { entry.reload.pic }
    end

    it 'is refused in a way fetch can detect, not a redirect it would follow' do
      # A 302 here is followed by fetch and lands on a 200, so `response.ok` would be true
      # and the caller would treat a refusal as success.
      patch update_position_entry_path(entry), params: { position: 2 }

      expect(response).not_to be_redirect
    end
  end

  describe 'the owner' do
    before { sign_in owner }

    it 'can still reorder' do
      create(:entry, list: list, position: 2, name: 'Second')

      patch update_position_entry_path(entry), params: { position: 2 }

      expect(response).to have_http_status(:ok)
      expect(entry.reload.position).to eq(2)
    end

    it 'can still flip the broken-link flag' do
      entry.update!(stream: false)

      patch reportlink_entry_path(entry)

      expect(entry.reload.stream).to be true
    end

    it 'can still change the provider' do
      other = Source.create!(name: 'Other', kind: 'imdb', active: true,
                             templates: { 'movie' => 'https://other.test/%{imdb}' })

      patch set_source_entry_path(entry), params: { source_id: other.id }

      expect(entry.reload.provider_id).to eq(other.id)
    end
  end

  describe 'an entry in a default list' do
    # Default lists are shared library content: anyone signed in may curate them.
    it 'stays editable by anyone' do
      shared = create(:list, user: owner, default: true)
      shared_entry = create(:entry, list: shared, position: 1, name: 'Shared')
      sign_in stranger

      patch reportlink_entry_path(shared_entry)

      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
