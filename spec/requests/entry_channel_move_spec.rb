require 'rails_helper'

# The Channel select on the entry edit form. For a long time the controller merged the
# entry's own list back over whatever was chosen, so a move saved nothing and said nothing.
RSpec.describe 'Moving an entry to another channel from the edit form', :needs_provider, type: :request do
  let(:user)      { create(:user) }
  let(:list)      { create(:list, user: user, name: 'Here') }
  let(:elsewhere) { create(:list, user: user, name: 'Elsewhere') }
  let!(:entry)    { create(:entry, list: list, name: 'Moving', position: 1, year: 1979) }
  let!(:staying)  { create(:entry, list: list, name: 'Staying', position: 2, year: 1975) }

  before { sign_in user }

  it 'moves the entry to the end of the chosen channel' do
    create(:entry, list: elsewhere, name: 'Already there', position: 1)

    patch entry_path(entry), params: { entry: { list_id: elsewhere.id, position: '1', note: 'Edited too' } }

    expect(entry.reload.list).to eq(elsewhere)
    expect(entry.position).to eq(2)
    expect(entry.note).to eq('Edited too')
    expect(staying.reload.position).to eq(2)
    expect(flash[:notice]).to include('moved to Elsewhere')
  end

  it 'takes the card off the page it was edited on' do
    patch entry_path(entry), params: { entry: { list_id: elsewhere.id } }, as: :turbo_stream

    removed = response.body.scan(/<turbo-stream action="remove" target="([^"]+)"/).flatten
    expect(removed).to include("entry_#{entry.id}", "row-entry_#{entry.id}")
    expect(response.body).to include("header-count-#{list.id}")
  end

  it 'leaves the entry where it is when the channel is unchanged' do
    patch entry_path(entry), params: { entry: { list_id: list.id, note: 'Just a note' } }

    expect(entry.reload.list).to eq(list)
    expect(entry.note).to eq('Just a note')
  end

  it 'refuses a channel the user cannot edit, and saves nothing else' do
    theirs = create(:list, name: 'Theirs')

    patch entry_path(entry), params: { entry: { list_id: theirs.id, note: 'Should not save' } }

    expect(entry.reload.list).to eq(list)
    expect(entry.note).to eq('Some note')
    expect(flash[:alert]).to include('cannot move')
  end

  # The select used to offer only the editor's own channels. Editing an entry in somebody
  # else's default channel, the browser picked the first of those instead, so with the
  # override gone a plain save would have moved the entry without anybody choosing to.
  it 'has the entry’s own channel selected even when the editor does not own it' do
    shared = create(:list, user: create(:user), name: 'Shared', default: true)
    shared_entry = create(:entry, list: shared, name: 'Shared entry', position: 1)

    get edit_entry_path(shared_entry, format: :text)

    selected = response.body[/<select[^>]*entry_list_id.*?<\/select>/m][/<option[^>]*selected[^>]*>/]
    expect(selected).to include(%(value="#{shared.id}"))
  end
end
