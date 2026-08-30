require 'rails_helper'

# In the order view a channel inside another is a row that opens in place. Its entries are
# fetched when the row is opened rather than shipped with the page collapsed: one of these
# channels holds 215 cards.
RSpec.describe 'Opening a channel inside a channel', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:parent) { create(:list, user: user, name: 'List of Lists') }
  let(:child) { create(:list, user: user, name: 'School Night In') }

  before do
    sign_in user
    create(:entry, list: parent, name: 'Alien', imdb: 'tt1', position: 1)
    create(:entry, list: child, name: 'Arrival', imdb: 'tt2', position: 1)
    child.add_to_parent(parent)
  end

  describe 'the row' do
    before { get list_path(parent, criteria: 'Position') }

    it 'offers a control that opens it' do
      expect(response.body).to include('channel-card__expand')
      expect(response.body).to include('data-action="section-collapse#toggle"')
      expect(response.body).to include('aria-expanded="false"')
    end

    it 'starts closed' do
      body = response.body[/<div class="nested-entries"[^>]*>/]

      expect(body).to include('hidden')
    end

    # The point of the frame: the parent page carries none of the channel's cards.
    it 'ships a lazy frame rather than the entries themselves' do
      expect(response.body).to include(list_nested_entries_path(child))
      expect(response.body).to include('loading="lazy"')
      expect(response.body).not_to include('<bold>Arrival</bold>')
    end
  end

  describe 'what the frame answers with' do
    it 'renders that channel’s entries, in its own order' do
      create(:entry, list: child, name: 'Solaris', imdb: 'tt3', position: 2)

      get list_nested_entries_path(child)

      expect(response).to be_successful
      expect(response.body).to include(%(<turbo-frame id="channel-entries-#{child.id}">))
      expect(response.body.index('Arrival')).to be < response.body.index('Solaris')
    end

    it 'leaves them unbadged: the row above them already says whose they are' do
      get list_nested_entries_path(child)

      expect(response.body).not_to include('entry-source')
    end

    it 'says so when the channel is empty' do
      get list_nested_entries_path(create(:list, user: user, name: 'Nothing Yet'))

      expect(response.body).to include('Nothing in this channel yet.')
    end

    it 'is a bare frame, with none of the page around it' do
      get list_nested_entries_path(child)

      expect(response.body).not_to include('<html')
      expect(response.body).not_to include('channelSidebar')
    end
  end
end
