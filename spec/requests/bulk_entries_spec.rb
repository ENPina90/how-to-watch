require 'rails_helper'

# The checkboxes on a channel's minimal view, and the two things they do: delete the ticked
# entries in one go, and set whichever fields were filled in on all of them.
RSpec.describe 'Bulk entry actions', :needs_provider, type: :request do
  let(:user)  { create(:user) }
  let(:list)  { create(:list, user: user) }
  let!(:first)  { create(:entry, list: list, name: 'First', position: 1, category: 'Drama', note: 'Keep me') }
  let!(:second) { create(:entry, list: list, name: 'Second', position: 2, category: 'Drama', note: 'Keep me too') }
  let!(:third)  { create(:entry, list: list, name: 'Third', position: 3, category: 'Drama') }

  before { sign_in user }

  describe 'the minimal view' do
    it 'offers a box per entry, the toolbar and the modal' do
      get list_path(list, view: 'minimal')

      expect(response.body.scan('data-bulk-select-target="checkbox"').size).to eq(3)
      expect(response.body).to include('bulk-toolbar', 'id="bulkEditModal"')
    end

    it 'leaves all of it out of the full view' do
      get list_path(list)

      expect(response.body).not_to include('data-bulk-select-target', 'id="bulkEditModal"')
    end

    it 'offers nothing to somebody who cannot edit the channel' do
      sign_in create(:user)

      get list_path(list, view: 'minimal')

      expect(response.body).not_to include('data-bulk-select-target', 'id="bulkEditModal"')
    end
  end

  describe 'deleting' do
    it 'removes every selected entry in one request and leaves the rest' do
      expect {
        delete list_bulk_entries_path(list), params: { entry_ids: [first.id, second.id] }
      }.to change(Entry, :count).by(-2)

      expect(Entry.exists?(third.id)).to be true
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to include('Deleted 2 entries')
    end

    it 'is not reachable over GET' do
      get "/lists/#{list.id}/bulk_entries", params: { entry_ids: [first.id] }

      expect(response).to have_http_status(:not_found)
      expect(Entry.exists?(first.id)).to be true
    end

    it 'deletes nothing when one of the ids belongs to somebody else' do
      theirs = create(:entry, list: create(:list), name: 'Theirs')

      expect {
        delete list_bulk_entries_path(list), params: { entry_ids: [first.id, theirs.id] }
      }.not_to change(Entry, :count)

      expect(flash[:alert]).to be_present
    end

    it 'refuses a channel that is not the user’s' do
      sign_in create(:user)

      expect {
        delete list_bulk_entries_path(list), params: { entry_ids: [first.id] }
      }.not_to change(Entry, :count)
    end
  end

  describe 'editing' do
    it 'sets only the fields that were filled in' do
      patch list_bulk_entries_path(list),
            params: { entry_ids: [first.id, second.id], entry: { category: 'Horror', note: '', length: '' } }

      expect([first.reload, second.reload].map(&:category)).to eq(%w[Horror Horror])
      expect(first.note).to eq('Keep me')
      expect(second.note).to eq('Keep me too')
      expect(first.length).to eq(143)
      expect(third.reload.category).to eq('Drama')
      expect(flash[:notice]).to include('Updated 2 entries')
    end

    it 'never renames anything' do
      patch list_bulk_entries_path(list),
            params: { entry_ids: [first.id], entry: { name: 'Renamed', note: 'Changed' } }

      expect(first.reload.name).to eq('First')
      expect(first.note).to eq('Changed')
    end

    it 'changes nothing when nothing was filled in' do
      patch list_bulk_entries_path(list), params: { entry_ids: [first.id], entry: { category: ' ' } }

      expect(first.reload.category).to eq('Drama')
      expect(flash[:alert]).to include('Nothing to change')
    end

    it 'can put the provider back to the channel default' do
      source = Source.create!(name: 'Other', kind: 'imdb', active: true,
                              templates: { 'movie' => 'https://other.test/%{imdb}' })
      first.update!(provider: source)

      patch list_bulk_entries_path(list),
            params: { entry_ids: [first.id], entry: { provider_id: BulkEntriesController::INHERIT_PROVIDER } }

      expect(first.reload.provider_id).to be_nil
    end

    it 'moves entries to the end of another channel, in their order here' do
      elsewhere = create(:list, user: user)
      create(:entry, list: elsewhere, name: 'Already there', position: 1)

      patch list_bulk_entries_path(list),
            params: { entry_ids: [second.id, first.id], entry: { list_id: elsewhere.id } }

      expect(first.reload.list).to eq(elsewhere)
      expect([first.position, second.reload.position]).to eq([2, 3])
    end

    it 'will not move entries into a channel the user cannot edit' do
      patch list_bulk_entries_path(list),
            params: { entry_ids: [first.id], entry: { list_id: create(:list).id } }

      expect(first.reload.list).to eq(list)
      expect(flash[:alert]).to include('cannot move')
    end

    it 'changes none of them when one refuses' do
      # Same name, different series: giving them the same series collides on the second.
      pilot_a = create(:entry, list: list, name: 'Pilot', series: 'A', position: 4)
      pilot_b = create(:entry, list: list, name: 'Pilot', series: 'B', position: 5)

      patch list_bulk_entries_path(list),
            params: { entry_ids: [pilot_a.id, pilot_b.id], entry: { series: 'C' } }

      expect([pilot_a.reload.series, pilot_b.reload.series]).to eq(%w[A B])
      expect(flash[:alert]).to include('Nothing was changed')
    end
  end
end
