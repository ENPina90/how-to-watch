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
end
