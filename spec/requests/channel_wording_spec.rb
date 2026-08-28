require 'rails_helper'

# The model is still List -- table, class, routes, params -- and only the word the reader
# sees is Channel. These pin the visible half so a later change cannot quietly put "list"
# back in front of anyone, and pin the identifiers that must stay put alongside it.
RSpec.describe 'Channel wording', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Noir') }

  before do
    sign_in user
    create(:entry, list: list, name: 'Alien', year: 1979, position: 1)
  end

  it 'names them Channels in the sidebar and on the index' do
    get lists_path

    expect(response.body).to include('Your Channels')
    expect(response.body).to include('>Channels<')
    expect(response.body).not_to include('Your Lists')
  end

  it 'calls the form buttons Create and Update Channel, which Rails builds from the model' do
    get new_list_path
    expect(response.body).to include('Create Channel')

    get edit_list_path(list)
    expect(response.body).to include('Update Channel')
  end

  it 'says channel in the form copy' do
    get new_list_path

    expect(response.body).to include('Optional description of this channel')
    expect(response.body).to include('Select a parent channel (optional)')
    expect(response.body).to include('Add to Channel')
  end

  it 'says channel in a flash' do
    post lists_path, params: { list: { name: 'Westerns' } }

    expect(flash[:notice]).to eq('Channel was successfully created.')
  end

  # The rename is skin deep on purpose: routes, params and the Stimulus wiring all still
  # say list, and the page breaks quietly if any of them are renamed along with the copy.
  it 'leaves the plumbing named list' do
    get list_path(list)

    expect(response.body).to include('data-controller="list-search"')
    expect(response.body).to include('data-list-search-user-lists-value')
    expect(response.body).to include(list_path(list))
    expect(response.body).to include('list-layout')
  end
end
