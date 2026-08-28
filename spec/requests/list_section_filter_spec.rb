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

  # Pressing a section starts a drag and every section the pointer crosses joins the
  # selection, so the rail needs the pointer pair as well as the click.
  it 'wires each toggle for a click and for a drag across the rail' do
    get list_path(list, criteria: 'Year', sort: 'asc')

    expect(response.body.scan('section-filter#toggle').count).to eq(2)
    expect(response.body.scan('pointerdown->section-filter#start').count).to eq(2)
    expect(response.body.scan('pointerenter->section-filter#extend').count).to eq(2)
  end

  # Collapsing hides the entries and leaves the heading, so the entries need a wrapper of
  # their own to hide -- the heading cannot be a sibling that goes with them.
  it 'gives each section a collapse toggle over a body of its own' do
    get list_path(list, criteria: 'Year', sort: 'asc')

    expect(response.body.scan('data-controller="section-collapse"').count).to eq(2)
    expect(response.body.scan(/<button[^>]*class="section-toggle"[^>]*aria-expanded="true"/m).count).to eq(2)
    expect(response.body.scan('data-section-collapse-target="body"').count).to eq(2)
  end

  describe 'when there is nothing to filter' do
    # The Order view groups nothing, but it still files entries under categories, and the
    # rail lists those in the order the entries run.
    it 'lists the categories of the order view, in the order they appear' do
      list.entries.update_all(category: 'Later')
      create(:entry, list: list, name: 'Solaris', category: 'Earlier', position: 0)

      get list_path(list, criteria: 'Position')

      expect(rail_keys).to eq(%w[Earlier Later])
    end

    it 'runs them backwards when the order does' do
      list.entries.update_all(category: 'Later')
      create(:entry, list: list, name: 'Solaris', category: 'Earlier', position: 0)

      get list_path(list, criteria: 'Position', sort: 'desc')

      expect(rail_keys).to eq(%w[Later Earlier])
    end

    it 'files an entry with no category of its own under Other' do
      list.entries.update_all(category: nil)

      get list_path(list, criteria: 'Position')

      expect(rail_keys).to eq(['Other'])
    end

    it 'leaves the filters out of a channel with no entries at all' do
      get list_path(create(:list, user: user), criteria: 'Position')

      expect(response.body).not_to include('channel-sidebar__filters')
    end

    it 'leaves them out of an empty channel, sections or not' do
      get list_path(create(:list, user: user), criteria: 'Year')

      expect(response.body).not_to include('channel-sidebar__filters')
    end

    # The sidebar itself stays: Up Next is the other half of it.
    it 'keeps the filters wherever there are sections' do
      get list_path(list, criteria: 'Year')

      expect(response.body).to include('channel-sidebar__filters')
      expect(response.body).to include('id="channelSidebar"')
    end
  end
end
