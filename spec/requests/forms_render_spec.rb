require 'rails_helper'

# simple_form drives every form in the app, with a customised bootstrap wrapper set
# (config/initializers/simple_form_bootstrap.rb). Controller specs do not render views, so
# without these a simple_form upgrade could break every form and the suite would stay green.
RSpec.describe 'Forms render', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  it 'renders the standalone entry edit form' do
    entry = create(:entry, list: list, position: 1)

    get edit_entry_path(entry)

    expect(response).to be_successful
    expect(response.body).to include('name="entry[name]"')
    expect(response.body).to include('name="entry[source_url]"')
  end

  it 'renders the modal entry form the edit controller fetches' do
    # edit_controller.js requests this as format.text and injects it into the modal.
    entry = create(:entry, list: list, position: 1)

    get edit_entry_path(entry, format: :text)

    expect(response).to be_successful
    expect(response.body).to include('name="entry[source_url]"')
    expect(response.body).to include('name="entry[provider_id]"')   # association select
    expect(response.body).to include('name="entry[source_key]"')
  end

  # The cable schedule lays a slot out by the runtime and guesses where there is none, and a
  # guess that is short cuts the programme off partway through. Both forms are permitted to
  # write `length` and neither offered anywhere to type it, so the only way to correct one
  # was the player happening to report it.
  describe 'the runtime field' do
    it 'offers a runtime on the standalone edit form' do
      entry = create(:entry, list: list, position: 1)

      get edit_entry_path(entry)

      expect(response.body).to include('name="entry[length]"')
    end

    it 'offers a runtime on the modal form' do
      entry = create(:entry, list: list, position: 1)

      get edit_entry_path(entry, format: :text)

      expect(response.body).to include('name="entry[length]"')
    end

    # A show has no runtime of its own -- its episodes do, and the schedule measures the
    # slot by whichever one it picked. Without a field per episode the modal could only set
    # the fallback.
    it 'offers a runtime against each episode of a series' do
      series = create(:entry, list: list, position: 1, media: 'series')
      first = Subentry.create!(entry: series, season: '1', episode: '1', name: 'Pilot')
      second = Subentry.create!(entry: series, season: '1', episode: '2', name: 'Second')

      get edit_entry_path(series, format: :text)

      expect(response.body).to include("name=\"entry[subentries_attributes][0][length]\"")
      expect(response.body).to include("name=\"entry[subentries_attributes][1][length]\"")
      expect(response.body).to include(first.id.to_s, second.id.to_s)
    end

    it 'saves a runtime typed against an episode' do
      series = create(:entry, list: list, position: 1, media: 'series')
      episode = Subentry.create!(entry: series, season: '1', episode: '1', name: 'Pilot')

      patch entry_path(series), params: {
        entry: { subentries_attributes: { '0' => { id: episode.id, length: '53' } } }
      }

      expect(episode.reload.length).to eq(53)
    end

    # Sixty-six fields in whatever order the database handed them back is no way to find the
    # one episode that is missing a runtime.
    it 'lists the episodes in order, with the blank row for adding one last' do
      series = create(:entry, list: list, position: 1, media: 'series')
      second = Subentry.create!(entry: series, season: '1', episode: '2', name: 'Second')
      first = Subentry.create!(entry: series, season: '1', episode: '1', name: 'Pilot')

      get edit_entry_path(series, format: :text)

      titles = response.body.scan(/value="([^"]*)" name="entry\[subentries_attributes\]\[\d+\]\[name\]"/)
      ids = response.body.scan(/value="(\d+)" name="entry\[subentries_attributes\]\[\d+\]\[id\]"/)

      expect(titles.flatten).to eq(%w[Pilot Second])
      expect(ids.flatten.map(&:to_i)).to eq([first.id, second.id])
    end

    # The blank row exists so an episode can be added; left alone it must not become a
    # nameless one. Judging that by the submitted fields rather than by the row being new
    # meant a request that set only a runtime destroyed the episode it was correcting.
    it 'keeps an episode when the request names only the field being changed' do
      series = create(:entry, list: list, position: 1, media: 'series')
      episode = Subentry.create!(entry: series, season: '1', episode: '1', name: 'Pilot')

      patch entry_path(series), params: {
        entry: { subentries_attributes: { '0' => { id: episode.id, length: '53' } } }
      }

      expect(Subentry.exists?(episode.id)).to be(true)
      expect(episode.reload.name).to eq('Pilot')
    end

    it 'still drops the blank row rather than saving a nameless episode' do
      series = create(:entry, list: list, position: 1, media: 'series')

      expect do
        patch entry_path(series), params: {
          entry: { subentries_attributes: { '0' => { name: '', season: '', episode: '' } } }
        }
      end.not_to change(Subentry, :count)
    end
  end

  it 'renders the new list form' do
    get new_list_path

    expect(response).to be_successful
    expect(response.body).to include('name="list[name]"')
    # boolean inputs come from the customised wrapper
    expect(response.body).to include('name="list[ordered]"')
  end

  it 'renders the list edit form' do
    get edit_list_path(list)

    expect(response).to be_successful
    expect(response.body).to include('name="list[description]"')
  end

  it 'renders the devise sign-in form' do
    sign_out user

    get new_user_session_path

    expect(response).to be_successful
    expect(response.body).to include('name="user[email]"')
    expect(response.body).to include('name="user[password]"')
  end

  # Nothing but the custom-entry form now. The search that used to sit on top of it -- one
  # box per media type, its own mustache templates, its own + buttons -- has gone: the navbar
  # search is on every page and reaches this form through "+ Details".
  describe 'the add-entry page' do
    it 'renders the custom-entry form' do
      get new_list_entry_path(list)

      expect(response).to be_successful
      expect(response.body).to include('name="entry[name]"')
      expect(response.body).to include('name="entry[media]"')
      expect(response.body).to include('name="custom"')
    end

    it 'carries no search box of its own' do
      get new_list_entry_path(list)

      expect(response.body).not_to include('data-search-target="input"')
      expect(response.body).not_to include('<template id="movieCardTemplate">')
    end

    # The poster fields the edit form and the change-poster modal already had: a link to
    # keep pointing at, a link to copy, and a file.
    it 'offers all three ways to a poster' do
      get new_list_entry_path(list)

      expect(response.body).to include('name="entry[pic]"')
      expect(response.body).to include('name="entry[poster_url]"')
      expect(response.body).to include('name="entry[poster]"')
    end

    # The submit lives up in the button row with the two CSV buttons, so it is attached to
    # the form by id rather than by being inside it.
    it 'submits from the button row above the fields' do
      get new_list_entry_path(list)

      expect(response.body).to include('id="custom-entry-form"')
      expect(response.body).to include('form="custom-entry-form"')
      expect(response.body).to include(csv_template_list_entries_path(list))
      expect(response.body).to include(import_csv_list_entries_path(list))
    end
  end

end
