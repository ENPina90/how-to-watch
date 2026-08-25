require 'rails_helper'

# The "Find a movie" box on a list submits ?query= as a plain GET. It had two halves and
# both were broken: search_controller#entries (the live filter) was deleted in 8803106 and
# left eight dangling data-actions behind, and the default Position view rendered
# `all_items_by_position` instead of the filtered set, so the server half returned the
# whole list unchanged.
RSpec.describe 'Filtering a list', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  def rendered_names(*names)
    names.select { |name| response.body.include?(%(<bold>#{name}</bold>)) }
  end

  before do
    create(:entry, list: list, name: 'Arrival', position: 1)
    create(:entry, list: list, name: 'Dune', position: 2)
  end

  it 'narrows the default position view to the match' do
    get list_path(list, query: 'Arrival')

    expect(response).to be_successful
    expect(rendered_names('Arrival', 'Dune')).to eq(['Arrival'])
  end

  it 'narrows a grouped view too' do
    get list_path(list, criteria: 'Genre', query: 'Arrival')

    expect(response).to be_successful
    expect(rendered_names('Arrival', 'Dune')).to eq(['Arrival'])
  end

  it 'renders the whole list when there is no query' do
    get list_path(list)

    expect(rendered_names('Arrival', 'Dune')).to eq(%w[Arrival Dune])
  end

  it 'matches on prefix, the way the pg_search scope is configured' do
    get list_path(list, query: 'Arri')

    expect(rendered_names('Arrival', 'Dune')).to eq(['Arrival'])
  end

  it 'renders an empty result rather than falling back to everything' do
    get list_path(list, query: 'Nothingmatchesthis')

    expect(response).to be_successful
    expect(rendered_names('Arrival', 'Dune')).to be_empty
  end

  it 'leaves child list cards out of a search' do
    # The child-list nav elsewhere on the page still lists them; this is about the cards
    # the position view mixes in with the entries.
    child = create(:list, user: user, name: 'Sequels')
    list.child_relationships.create!(child_list: child, position: 3)

    get list_path(list)
    expect(response.body).to include('card mb-4 border-primary')

    get list_path(list, query: 'Arrival')
    expect(response.body).not_to include('card mb-4 border-primary')
  end

  it 'keeps the criteria links as ordinary navigation' do
    # They used to carry click->search#entries, which no longer existed.
    get list_path(list)

    expect(response.body).to include(list_path(list, criteria: 'Year'))
    expect(response.body).not_to include('search#entries')
  end
end
