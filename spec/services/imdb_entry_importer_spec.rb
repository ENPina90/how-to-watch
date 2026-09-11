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

  # A series row on its own has nothing to play: the episodes carry the season and episode
  # numbers a provider's template asks for. Without them a show lands in a channel looking
  # right and is off air the moment anybody opens it.
  it 'brings a series\' episodes with it' do
    allow(OmdbApi).to receive(:get_movie).and_return(omdb_payload.merge('Type' => 'series'))
    expect(OmdbApi).to receive(:get_series_episodes).with(an_instance_of(Entry))

    result = described_class.new(list: list, imdb_id: 'tt0848228').call

    expect(result[:status]).to eq(:created)
    expect(result[:entry].media).to eq('series')
  end

  it 'asks for no episodes when the entry is a film' do
    expect(OmdbApi).not_to receive(:get_series_episodes)

    described_class.new(list: list, imdb_id: 'tt0848228').call
  end

  # The entry itself was created. Losing the episodes is a reason to log, not a reason to
  # throw the row away and report that nothing was added.
  it 'keeps the series when the episode import fails' do
    allow(OmdbApi).to receive(:get_movie).and_return(omdb_payload.merge('Type' => 'series'))
    allow(OmdbApi).to receive(:get_series_episodes).and_raise(StandardError, 'OMDB down')

    result = described_class.new(list: list, imdb_id: 'tt0848228').call

    expect(result[:status]).to eq(:created)
    expect(result[:entry]).to be_persisted
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
