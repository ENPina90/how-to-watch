require 'rails_helper'

# A rating and a runtime are near enough unique per entry, so grouping by the value itself
# made a section per entry -- 41 rating sections on one channel here. They bucket the way
# years bucket into decades: half a point, and ten minutes.
RSpec.describe 'Rating and length in bands', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  def sections
    response.body.scan(/<section class="entry-section"\s+id="[^"]*"\s+data-section="([^"]*)"/m).flatten
  end

  describe 'rating' do
    it 'puts half a point in one band, named by its floor' do
      create(:entry, list: list, name: 'A', imdb: 'tt1', rating: 8.1, position: 1)
      create(:entry, list: list, name: 'B', imdb: 'tt2', rating: 8.4, position: 2)
      create(:entry, list: list, name: 'C', imdb: 'tt3', rating: 8.6, position: 3)

      get list_path(list, criteria: 'Rating', sort: 'asc')

      expect(sections).to eq(['8.0', '8.5'])
    end

    # Numeric keys, so they sort as numbers: as text, "10.0" comes before "8.0".
    it 'orders ten above eight' do
      create(:entry, list: list, name: 'A', imdb: 'tt1', rating: 8.2, position: 1)
      create(:entry, list: list, name: 'B', imdb: 'tt2', rating: 10.0, position: 2)

      get list_path(list, criteria: 'Rating', sort: 'asc')

      expect(sections).to eq(['8.0', '10.0'])
    end

    it 'files an unrated entry under Other' do
      create(:entry, list: list, name: 'A', imdb: 'tt1', rating: nil, position: 1)

      get list_path(list, criteria: 'Rating')

      expect(sections).to eq(['Other'])
    end
  end

  describe 'length' do
    it 'puts ten minutes in one band' do
      create(:entry, list: list, name: 'A', imdb: 'tt1', length: 91, position: 1)
      create(:entry, list: list, name: 'B', imdb: 'tt2', length: 99, position: 2)
      create(:entry, list: list, name: 'C', imdb: 'tt3', length: 143, position: 3)

      get list_path(list, criteria: 'Length', sort: 'asc')

      expect(sections).to eq(['90', '140'])
    end

    it 'files one with no runtime under Other' do
      create(:entry, list: list, name: 'A', imdb: 'tt1', length: nil, position: 1)

      get list_path(list, criteria: 'Length')

      expect(sections).to eq(['Other'])
    end
  end

  describe 'how the bands are labelled' do
    before do
      create(:entry, list: list, name: 'A', imdb: 'tt1', length: 91, rating: 8.2, position: 1)
    end

    # The key is what the filter matches on, so the unit is added to the label rather than
    # baked into the value.
    it 'says Min after a runtime, in the rail and over the cards' do
      get list_path(list, criteria: 'Length')

      expect(response.body).to include('data-section="90"')
      expect(response.body).to include('>90 Min<')
      expect(response.body).to include('90 Min <small')
    end

    it 'leaves Other alone, which is not a number of minutes' do
      create(:entry, list: list, name: 'B', imdb: 'tt2', length: nil, position: 2)

      get list_path(list, criteria: 'Length')

      expect(response.body).not_to include('Other Min')
    end

    it 'adds nothing to a rating' do
      get list_path(list, criteria: 'Rating')

      expect(response.body).to include('data-section="8.0"')
      expect(response.body).not_to include('8.0 Min')
    end

    it 'names the grouping in the filter heading' do
      get list_path(list, criteria: 'Length')
      expect(response.body).to include('Filter by Length</h6>')

      get list_path(list, criteria: 'Position')
      expect(response.body).to include('Filter by Order</h6>')
    end
  end

  # The page groups and the streams place cards; both have to read the same bands.
  it 'streams a new card into the band the page would have put it in' do
    entry = create(:entry, list: list, name: 'A', imdb: 'tt1', rating: 8.4, length: 91, position: 1)

    expect(entry.section_keys('Rating')).to eq([8.0])
    expect(entry.section_keys('Length')).to eq([90])
  end
end
