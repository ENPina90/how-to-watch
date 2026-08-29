require 'rails_helper'

# A channel holding a mix of entries and other channels: the channels in it are part of the
# page like everything else -- the filters claim them, and Up Next can suggest them.
RSpec.describe 'A channel of channels', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'List of Lists') }
  let(:child) { create(:list, user: user, name: 'AmAn') }

  before do
    sign_in user
    create(:entry, list: list, name: 'Alien', year: 1979, category: 'Horror', position: 2)
    create(:entry, list: child, name: 'Cowboy Bebop', position: 1)
    child.add_to_parent(list)
    list.child_relationships.find_by(child_list: child).update!(position: 1)
  end

  def rail_keys
    response.body.scan(/<button[^>]*class="section-filter"[^>]*data-section="([^"]*)"/m).flatten
  end

  describe 'the filters' do
    it 'lists Channels alongside the categories in the order view' do
      get list_path(list, criteria: 'Position')

      expect(rail_keys).to include('Channels')
      expect(rail_keys).to include('Horror')
    end

    it 'lists it in a grouped view too, where no grouping can read a channel' do
      get list_path(list, criteria: 'Year')

      expect(rail_keys.first).to eq('Channels')
      expect(rail_keys).to include('1970s')
    end

    it 'leaves it out of a channel with no channels in it' do
      get list_path(create(:list, user: user).tap { |l| create(:entry, list: l, position: 1) },
                    criteria: 'Position')

      expect(rail_keys).not_to include('Channels')
    end
  end

  # The filter hides by section, so a channel's card has to be in one to be hidden with the
  # rest -- it used to be the one card no filter could touch.
  it 'gives a channel card the same wrapper an entry card gets' do
    get list_path(list, criteria: 'Position')

    wrapper = response.body[/<div class="position-item"\s+data-section="Channels".*?<\/div>/m]

    expect(wrapper).to be_present
    expect(wrapper).to include('data-section-filter-target="section"')
    expect(wrapper).to include('channel-card')
  end

  it 'wraps them in a grouped view as well, where they sit above the sections' do
    get list_path(list, criteria: 'Year')

    expect(response.body).to include('data-section="Channels"')
    expect(response.body).to include('child-channels')
  end

  # Up Next reads the page: a channel card is a card like any other, and nothing about a
  # channel is ever "watched".
  it 'keeps Up Next on a channel that holds only other channels' do
    only_channels = create(:list, user: user, name: 'Nothing But Channels')
    child.add_to_parent(only_channels)

    get list_path(only_channels)

    expect(response.body).to include('channel-sidebar__section--upnext')
  end
end
