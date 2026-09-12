require 'rails_helper'

# The custom-entry form opens filled in from the API and *nothing is created*. Everything
# below leans on that: the count of entries never moves.
RSpec.describe EntryPrefill do
  let(:list) { create(:list) }

  let(:omdb_payload) do
    {
      'Type' => 'movie',
      'Title' => 'Blade Runner',
      'imdbID' => 'tt0083658',
      'Year' => '1982',
      'Poster' => 'https://example.test/blade.jpg',
      'Genre' => 'Sci-Fi',
      'Director' => 'Ridley Scott',
      'Writer' => 'Hampton Fancher',
      'Actors' => 'Harrison Ford',
      'Plot' => 'A blade runner must pursue six replicants.',
      'Runtime' => '117 min',
      'imdbRating' => '8.1',
      'Language' => 'English'
    }
  end

  describe 'a blank form' do
    it 'builds an unsaved entry on the list when nothing was asked for' do
      result = described_class.new(list: list).call

      expect(result.entry).to be_a(Entry)
      expect(result.entry).not_to be_persisted
      expect(result.entry.list).to eq(list)
      expect(result.error).to be_nil
    end
  end

  describe 'a film' do
    before { allow(OmdbApi).to receive(:get_movie).with('tt0083658').and_return(omdb_payload) }

    it 'fills the form in without creating anything' do
      expect { described_class.new(list: list, imdb: 'tt0083658', tmdb: '78').call }
        .not_to change(Entry, :count)
    end

    it 'carries the fields the form offers' do
      entry = described_class.new(list: list, imdb: 'tt0083658', tmdb: '78').call.entry

      expect(entry.name).to eq('Blade Runner')
      expect(entry.media).to eq('movie')
      expect(entry.imdb).to eq('tt0083658')
      expect(entry.tmdb).to eq('78')
      expect(entry.year).to eq(1982)
      expect(entry.length).to eq(117)
      expect(entry.pic).to eq('https://example.test/blade.jpg')
      expect(entry.director).to eq('Ridley Scott')
      expect(entry.rating).to eq(8.1)
    end

    # OMDB says 'N/A' where it has no poster, and that would otherwise be typed into the
    # poster field as though it were an address.
    it 'leaves the poster field empty rather than typing N/A into it' do
      allow(OmdbApi).to receive(:get_movie).and_return(omdb_payload.merge('Poster' => 'N/A'))

      entry = described_class.new(list: list, imdb: 'tt0083658').call.entry

      expect(entry.pic).to be_nil
    end
  end

  describe 'a series the search tab called anime' do
    before do
      allow(OmdbApi).to receive(:get_movie).and_return(
        omdb_payload.merge('Type' => 'series', 'Title' => 'Cowboy Bebop', 'totalSeasons' => '1')
      )
    end

    it 'takes the media type from the tab OMDB cannot tell apart' do
      entry = described_class.new(list: list, imdb: 'tt0213338', type: 'anime').call.entry

      expect(entry.media).to eq('anime')
    end
  end

  describe 'a standalone episode' do
    let(:tmdb) do
      instance_double(TmdbService,
                      fetch_show: { 'name' => 'Severance' },
                      fetch_episode: {
                        'name' => 'Good News About Hell',
                        'overview' => 'Mark is promoted.',
                        'still_path' => '/still.jpg',
                        'vote_average' => 8.1,
                        'air_date' => '2022-02-18',
                        'runtime' => 57
                      })
    end

    # The card in the overlay carries the *series'* imdb id, so OMDB would describe the
    # series. TMDB is asked about the episode instead.
    it 'asks TMDB rather than OMDB' do
      expect(OmdbApi).not_to receive(:get_movie)

      entry = described_class.new(
        list: list, imdb: 'tt11280740', tmdb: '95396', season: '1', episode: '1', tmdb_service: tmdb
      ).call.entry

      expect(entry.media).to eq('episode')
      expect(entry.name).to eq('Severance - Good News About Hell')
      expect(entry.series).to eq('Severance')
      expect(entry.series_imdb).to eq('tt11280740')
      expect(entry.season).to eq(1)
      expect(entry.episode).to eq(1)
      expect(entry.length).to eq(57)
      expect(entry.year).to eq(2022)
    end
  end

  describe 'when the lookup comes back empty' do
    it 'says so and still hands back a form' do
      allow(OmdbApi).to receive(:get_movie).and_return(nil)

      result = described_class.new(list: list, imdb: 'tt0000000').call

      expect(result.error).to be_present
      expect(result.entry).to be_a(Entry)
      expect(result.entry.imdb).to eq('tt0000000')
    end

    it 'survives the API falling over' do
      allow(OmdbApi).to receive(:get_movie).and_raise(SocketError, 'no route')

      result = described_class.new(list: list, imdb: 'tt0083658').call

      expect(result.error).to be_present
      expect(result.entry).not_to be_persisted
    end
  end
end
