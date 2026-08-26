require 'rails_helper'

# The left rail filters the entries in place: every section is rendered, and clicking one
# hides the rest client-side. That only works while the rail's buttons and the sections
# they control agree on a key, which is what these guard.
RSpec.describe 'Filtering a list by section', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before do
    sign_in user
    create(:entry, list: list, name: 'Alien', year: 1979, position: 1)
    create(:entry, list: list, name: 'Arrival', year: 2016, position: 2)
  end

  def rail_keys
    response.body.scan(/<button[^>]*class="section-filter"[^>]*data-section="([^"]*)"/m).flatten
  end

  def section_keys
    response.body.scan(/<section class="entry-section"\s+data-section="([^"]*)"/m).flatten
  end

  it 'offers one toggle per section' do
    get list_path(list, criteria: 'Year', sort: 'asc')

    expect(rail_keys).to eq(%w[1970s 2010s])
  end

  it 'names the sections with the keys the toggles carry' do
    get list_path(list, criteria: 'Year', sort: 'asc')

    expect(section_keys).to eq(rail_keys)
  end

  it 'keeps the pair in step for any grouping' do
    get list_path(list, criteria: 'Genre', sort: 'asc')

    expect(rail_keys).to be_present
    expect(section_keys).to eq(rail_keys)
  end

  it 'renders every section, filtered or not -- the rail hides them client-side' do
    get list_path(list, criteria: 'Year', sort: 'asc', section: '1970s')

    expect(section_keys).to eq(%w[1970s 2010s])
  end

  # Collapsing hides the entries and leaves the heading, so the entries need a wrapper of
  # their own to hide -- the heading cannot be a sibling that goes with them.
  it 'gives each section a collapse toggle over a body of its own' do
    get list_path(list, criteria: 'Year', sort: 'asc')

    expect(response.body.scan('data-controller="section-collapse"').count).to eq(2)
    expect(response.body.scan(/<button[^>]*class="section-toggle"[^>]*aria-expanded="true"/m).count).to eq(2)
    expect(response.body.scan('data-section-collapse-target="body"').count).to eq(2)
  end

  it 'has no rail in the position view, which has no sections' do
    get list_path(list, criteria: 'Position')

    expect(rail_keys).to be_empty
  end
end
