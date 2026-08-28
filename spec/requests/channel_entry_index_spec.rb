require 'rails_helper'

# A search result the channel already holds offers to remove it rather than add it again,
# the way the /entries/new results do. The overlay asks the channel what it holds the first
# time you search from it -- rather than every page carrying the answer, which on a
# thousand-entry channel is a large attribute to ship to visits that never search.
RSpec.describe 'What a channel already holds', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Trek') }

  before { sign_in user }

  def index
    JSON.parse(response.body)
  end

  it 'answers with what a result can be matched on' do
    entry = create(:entry, list: list, imdb: 'tt0078748', position: 1)

    get list_entry_index_path(list)

    expect(response).to be_successful
    expect(index).to eq([{ 'id' => entry.id, 'imdb' => 'tt0078748', 'series_imdb' => nil,
                           'season' => nil, 'episode' => nil }])
  end

  # Every episode of a show is filed under the same imdb id, so the run position is what
  # tells two of them apart.
  it 'carries the run position of an episode' do
    create(:entry, list: list, media: 'episode', imdb: 'tt0708442',
                   series_imdb: 'tt0092455', season: 3, episode: 15, position: 1)

    get list_entry_index_path(list)

    expect(index.first).to include('series_imdb' => 'tt0092455', 'season' => 3, 'episode' => 15)
  end

  # The overlay builds this path by hand.
  it 'lives where the search controller looks for it' do
    expect(list_entry_index_path(list)).to eq("/lists/#{list.id}/entry_index")
  end

  it 'is empty for an empty channel' do
    get list_entry_index_path(list)

    expect(index).to be_empty
  end

  describe 'the buttons it drives' do
    before do
      create(:entry, list: list, position: 1)
      get list_path(list)
    end

    it 'offers a remove button for a result the channel holds' do
      expect(response.body.scan('click->list-search#remove').count).to eq(3)
      expect(response.body.scan('{{#entryId}}').count).to eq(3)
    end

    it 'keeps the add button for one it does not' do
      expect(response.body.scan('{{^entryId}}').count).to eq(3)
      expect(response.body.scan('click->list-search#add"').count).to eq(4)
    end
  end
end
