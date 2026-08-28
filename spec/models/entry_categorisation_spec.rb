require 'rails_helper'

# Everything that belongs to a show is filed under that show: a series, a season of one,
# and an episode all take the show's name as their category unless they were given one.
RSpec.describe 'Filing an entry under its show', :needs_provider do
  let(:list) { create(:list) }

  describe 'a series' do
    it 'is its own series, and takes its own name as its category' do
      entry = create(:entry, list: list, media: 'series', name: 'Star Trek', series: nil, category: nil)

      expect(entry.series).to eq('Star Trek')
      expect(entry.category).to eq('Star Trek')
    end

    it 'keeps a name it was given, when the two already differ' do
      # This is what a season is: a `series` row whose name carries the season number.
      entry = create(:entry, list: list, media: 'series', name: 'Star Trek - Season 3',
                             series: 'Star Trek', category: nil)

      expect(entry.name).to eq('Star Trek - Season 3')
      expect(entry.category).to eq('Star Trek')
    end
  end

  it 'files an anime the same way' do
    entry = create(:entry, list: list, media: 'anime', name: 'Cowboy Bebop', series: nil, category: nil)

    expect(entry.category).to eq('Cowboy Bebop')
  end

  it 'files an episode under its series rather than its own title' do
    entry = create(:entry, list: list, media: 'episode', name: 'Star Trek - The Cage',
                           series: 'Star Trek', season: 1, episode: 1, category: nil)

    expect(entry.category).to eq('Star Trek')
  end

  it 'leaves a category that was given' do
    entry = create(:entry, list: list, media: 'series', name: 'Star Trek', category: 'Comfort')

    expect(entry.category).to eq('Comfort')
  end

  it 'leaves a movie alone, which belongs to no show' do
    entry = create(:entry, list: list, media: 'movie', name: 'Alien', series: nil, category: nil)

    expect(entry.category).to be_nil
    expect(entry.series).to be_nil
  end

  # A category cleared by hand later is a decision, not a gap to fill again.
  it 'does not refill one cleared after the fact' do
    entry = create(:entry, list: list, media: 'series', name: 'Star Trek')
    entry.update!(category: nil)

    expect(entry.reload.category).to be_nil
  end
end
