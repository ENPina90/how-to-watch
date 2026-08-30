require 'rails_helper'

# A channel inside a channel lends its entries to the page. They are borrowed by the query
# rather than copied -- an entry keeps one home -- so taking the channel back out is one
# relationship row and touches no entry.
RSpec.describe 'Entries borrowed from a channel inside a channel', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:parent) { create(:list, user: user, name: 'List of Lists') }
  let(:child) { create(:list, user: user, name: 'School Night In') }

  before do
    sign_in user
    create(:entry, list: parent, name: 'Alien', imdb: 'tt1', year: 1979, position: 1)
    create(:entry, list: child, name: 'Arrival', imdb: 'tt2', year: 2016, position: 1)
    child.add_to_parent(parent)
  end

  describe 'a grouped view' do
    it 'groups the channel and everything inside it as one set' do
      get list_path(parent, criteria: 'Year')

      expect(response.body).to include('<bold>Alien</bold>')
      expect(response.body).to include('<bold>Arrival</bold>')
      expect(response.body).to include('data-section="1970s"')
      expect(response.body).to include('data-section="2010s"')
    end

    it 'marks a borrowed entry with the channel it lives in' do
      get list_path(parent, criteria: 'Year')

      expect(response.body).to include('entry-source')
      expect(response.body).to include('School Night In')
    end

    it 'leaves the channel’s own entries unmarked' do
      get list_path(parent, criteria: 'Year')

      alien = response.body[/<bold>Alien<\/bold>.{0,400}/m]
      expect(alien).not_to include('entry-source')
    end
  end

  # The Order view is a sequence of this channel's own positions, and a borrowed entry
  # carries numbering from somewhere else.
  describe 'the order view' do
    it 'shows this channel’s own entries and a row for the channel' do
      get list_path(parent, criteria: 'Position')

      expect(response.body).to include('<bold>Alien</bold>')
      expect(response.body).not_to include('<bold>Arrival</bold>')
      expect(response.body).to include('channel-card')
    end
  end

  it 'searches everything on the page, not one drawer of it' do
    get list_path(parent, query: 'Arrival')

    expect(response.body).to include('<bold>Arrival</bold>')
  end

  it 'counts everything under the channel in its title' do
    expect(parent.total_entry_count).to eq(2)

    get list_path(parent)

    expect(response.body).to include('header-count')
  end

  describe 'taking the channel back out' do
    it 'takes its entries off the page and leaves them where they live' do
      child.remove_from_parent(parent)

      get list_path(parent, criteria: 'Year')

      expect(response.body).not_to include('<bold>Arrival</bold>')
      expect(child.reload.entries.pluck(:name)).to eq(['Arrival'])
      expect(parent.total_entry_count).to eq(1)
    end
  end

  describe 'how deep it reads' do
    it 'gathers a channel inside a channel inside a channel' do
      grandchild = create(:list, user: user, name: 'Deeper')
      create(:entry, list: grandchild, name: 'Solaris', imdb: 'tt3', position: 1)
      grandchild.add_to_parent(child)

      expect(parent.total_entry_count).to eq(3)
    end

    it 'gathers a channel held twice only once' do
      other = create(:list, user: user, name: 'Also Here')
      child.add_to_parent(other)
      other.add_to_parent(parent)

      expect(parent.total_entry_count).to eq(2)
    end

    it 'stops rather than looping, whatever the database holds' do
      # Saved past the validation: adding this through the app is refused, and the read
      # should not be relying on that having always been true.
      ListRelationship.new(parent_list: child, child_list: parent, position: 1).save!(validate: false)

      expect { parent.total_entry_count }.not_to raise_error
    end
  end
end
