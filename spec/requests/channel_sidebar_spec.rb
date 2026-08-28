require 'rails_helper'

# Up Next and the section filters were two columns flanking the entries; they are one right
# sidebar now, shaped like the watch page's. The logic behind both is unchanged, which is
# why the filters still render inside the element that owns them.
RSpec.describe 'The channel sidebar', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Noir') }

  before do
    sign_in user
    create(:entry, list: list, name: 'Alien', year: 1979, position: 1)
  end

  it 'holds the filters above Up Next' do
    get list_path(list, criteria: 'Year')

    sidebar = response.body[/<aside id="channelSidebar".*?<\/aside>/m]

    expect(sidebar).to include('>Filters</h6>')
    expect(sidebar.index('channel-sidebar__filters')).to be < sidebar.index('Up Next')
  end

  # Filters give up the room; Up Next keeps its place at the bottom whatever the channel is
  # grouped by.
  it 'scrolls the filters rather than the panel' do
    get list_path(list, criteria: 'Year')

    expect(response.body).to include('channel-sidebar__section--filters')
    expect(response.body).to include('channel-sidebar__section--upnext')
  end

  it 'collapses and comes back' do
    get list_path(list)

    expect(response.body).to include('click->channel-sidebar#collapse')
    expect(response.body).to include('click->channel-sidebar#expand')
    expect(response.body).to include('id="channelSidebarExpand"')
  end

  # The filters are targets of the section-filter controller: rendered outside its element
  # they would silently stop working, so the sidebar sits inside that row despite being
  # positioned out of the flow.
  it 'keeps the filters inside the controller that owns them' do
    get list_path(list, criteria: 'Year')

    row = response.body[/<div class="row justify-content-center list-layout"[^>]*>.*<\/div>/m]

    expect(row).to include('data-controller="section-filter"')
    expect(row.index('data-controller="section-filter"')).to be < row.index('data-section-filter-target="option"')
  end

  it 'keeps Up Next inside its own controller' do
    get list_path(list)

    section = response.body[/<section class="channel-sidebar__section channel-sidebar__section--upnext"\s+data-controller="randomize">.*?<\/section>/m]

    expect(section).to include('data-randomize-target="picks"')
    expect(section).to include('click->randomize#upnext')
  end

  it 'is left out of the mobile view, which has no room for it' do
    get list_path(list, view: 'minimal')

    expect(response.body).not_to include('id="channelSidebar"')
  end
end
