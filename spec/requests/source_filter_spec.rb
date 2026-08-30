require 'rails_helper'

# A grouped view puts entries from several channels in one section, so "which channel is
# this from" becomes a filter of its own -- ANDed with the sections, not folded into them.
RSpec.describe 'Filtering by which channel an entry came from', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:parent) { create(:list, user: user, name: 'List of Lists') }
  let(:child) { create(:list, user: user, name: 'School Night In') }

  before do
    sign_in user
    create(:entry, list: parent, name: 'Alien', imdb: 'tt1', year: 1979, position: 1)
    create(:entry, list: child, name: 'Arrival', imdb: 'tt2', year: 2016, position: 1)
    child.add_to_parent(parent)
  end

  def source_buttons
    response.body.scan(/data-source="(\d+)"\s+data-section-filter-target="source"/).flatten
  end

  it 'offers each channel that lent something, this one included' do
    get list_path(parent, criteria: 'Year')

    expect(source_buttons).to contain_exactly(parent.id.to_s, child.id.to_s)
    expect(response.body).to include('>From</h6>')
  end

  it 'leaves a channel out that lent nothing' do
    empty = create(:list, user: user, name: 'Nothing Yet')
    empty.add_to_parent(parent)

    get list_path(parent, criteria: 'Year')

    expect(source_buttons).not_to include(empty.id.to_s)
  end

  it 'says nothing where there is only one channel to be from' do
    get list_path(create(:list, user: user).tap { |l| create(:entry, list: l, position: 1) },
                  criteria: 'Year')

    expect(response.body).not_to include('>From</h6>')
  end

  # Nothing is borrowed in the order view: a channel inside this one is a row that opens.
  it 'says nothing in the order view' do
    get list_path(parent, criteria: 'Position')

    expect(response.body).not_to include('>From</h6>')
  end

  # The filter hides one card at a time, so each needs a wrapper of its own: the section
  # around them holds entries from several channels.
  it 'tags every card in a grouped view with the channel it lives in' do
    get list_path(parent, criteria: 'Year')

    expect(response.body).to include(%(data-source="#{parent.id}" data-section-filter-target="card"))
    expect(response.body).to include(%(data-source="#{child.id}" data-section-filter-target="card"))
  end
end
