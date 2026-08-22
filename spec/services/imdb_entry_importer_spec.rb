require 'rails_helper'

RSpec.describe ImdbEntryImporter do
  let(:list) { create(:list) }
  let(:omdb_payload) do
    {
      'Type' => 'movie', 'Title' => 'The Avengers', 'imdbID' => 'tt0848228', 'Year' => '2012',
      'Poster' => 'https://example.com/poster.jpg', 'Genre' => 'Action', 'Director' => 'Joss Whedon',
      'Writer' => 'Joss Whedon', 'Actors' => 'Cast', 'Plot' => 'Heroes assemble.',
      'Runtime' => '143 min', 'imdbRating' => '8.0', 'Language' => 'English'
    }
  end

  before { allow(OmdbApi).to receive(:get_movie).and_return(omdb_payload) }

  it 'creates the entry in the given list' do
    result = described_class.new(list: list, imdb_id: 'tt0848228').call

    expect(result[:status]).to eq(:created)
    expect(result[:entry].name).to eq('The Avengers')
    expect(result[:entry].list).to eq(list)
    expect(result[:message]).to eq("Added to #{list.name}")
  end

  it 'stores the tmdb id it was given' do
    # Regression: both callers used to set "tmdb_id", a key the normalizer never reads, so
    # entries added from search arrived with no tmdb id at all.
    result = described_class.new(list: list, imdb_id: 'tt0848228', tmdb_id: '24428').call

    expect(result[:entry].tmdb).to eq('24428')
  end

  it 'reports not_found when OMDB has nothing' do
    allow(OmdbApi).to receive(:get_movie).and_return(nil)

    expect {
      result = described_class.new(list: list, imdb_id: 'tt0000000').call
      expect(result[:status]).to eq(:not_found)
    }.not_to change(Entry, :count)
  end

  it 'reports failure when the entry cannot be created' do
    allow(Entry).to receive(:create_from_source).and_return('Failed to create movie entry: boom')

    result = described_class.new(list: list, imdb_id: 'tt0848228').call

    expect(result[:status]).to eq(:failed)
    expect(result[:entry]).to be_nil
  end

  it 'does not raise when OMDB blows up' do
    allow(OmdbApi).to receive(:get_movie).and_raise(StandardError, 'connection reset')

    expect { expect(described_class.new(list: list, imdb_id: 'tt0848228').call[:status]).to eq(:failed) }
      .not_to raise_error
  end
end
