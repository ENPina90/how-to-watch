require 'rails_helper'

# Deleting a list bulk-deletes its whole entry graph in FK-safe order (see
# List#bulk_delete_entry_graph). This is the guard for that path: it is easy to leave a
# dangling reference behind and only find out when a real delete raises in production.
RSpec.describe 'Destroying a list', type: :model do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  it 'removes the entries, subentries and per-user tracking without an FK error' do
    entry = create(:entry, list: list, media: 'series', position: 1)
    subentry = Subentry.create!(entry: entry, season: '1', episode: '1', name: 'Pilot')
    entry.update!(current: subentry)

    UserEntryPosition.create!(user: user, entry: entry, current_subentry: subentry)
    entry.mark_completed_by!(user)
    list.position_for_user!(user)

    expect { list.destroy }.to change(Entry, :count).by(-1)

    expect(Subentry.where(id: subentry.id)).to be_empty
    expect(UserEntry.where(entry_id: entry.id)).to be_empty
    expect(UserEntryPosition.where(entry_id: entry.id)).to be_empty
    expect(UserListPosition.where(list_id: list.id)).to be_empty
  end

  it 'removes a list that other lists point at' do
    child = create(:list, user: user, name: 'Child')
    child.add_to_parent(list)

    expect { list.destroy }.not_to raise_error
    expect(List.where(id: child.id)).to exist
  end
end
