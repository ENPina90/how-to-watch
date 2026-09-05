require 'rails_helper'

RSpec.describe PosterCandidates do
  let(:list) { create(:list) }
  let(:entry) { create(:entry, list: list, tmdb: '299536', imdb: 'tt4154756', position: 3) }

  let(:tmdb) do
    instance_double(TmdbService,
                    fetch_poster_url: 'https://image.tmdb.org/t/p/w500/primary.jpg',
                    fetch_images: { 'posters' => [{ 'file_path' => '/alt1.jpg' }, { 'file_path' => '/alt2.jpg' }] },
                    find_by_imdb_id: { 'movie_results' => [{ 'poster_path' => '/via-imdb.jpg' }] },
                    fetch_omdb_poster_url: 'https://omdb.example/poster.jpg',
                    search_movie: { 'results' => [] },
                    search_tv: { 'results' => [] },
                    fetch_episode: {},
                    fetch_season: {})
  end

  let(:image_search) { instance_double(GoogleImageSearch, call: []) }

  before { allow(OmdbApi).to receive(:search_with_posters).and_return([]) }

  subject(:candidates) { described_class.new(entry, tmdb: tmdb, image_search: image_search).call }

  def sources = candidates.map { |c| c[:source] }

  it 'offers the TMDB poster first, then alternates' do
    expect(candidates.first).to eq({ url: 'https://image.tmdb.org/t/p/w500/primary.jpg', source: 'TMDB' })
    expect(candidates.map { |c| c[:url] }).to include('https://image.tmdb.org/t/p/w500/alt1.jpg')
  end

  it 'includes art found via the imdb id and OMDB' do
    expect(sources).to include('TMDB (via IMDB)')
    expect(sources).to include('OMDB')
  end

  it 'de-duplicates by url' do
    allow(tmdb).to receive(:fetch_omdb_poster_url).and_return('https://image.tmdb.org/t/p/w500/primary.jpg')

    urls = candidates.map { |c| c[:url] }

    expect(urls.uniq).to eq(urls)
  end

  it 'uses the tv endpoints for a series' do
    entry.update!(media: 'series')

    described_class.new(entry, tmdb: tmdb, image_search: image_search).call

    expect(tmdb).to have_received(:fetch_poster_url).with('299536', 'tv')
  end

  it 'offers no more than it can usefully show at once' do
    allow(tmdb).to receive(:fetch_images).and_return(
      { 'posters' => Array.new(40) { |i| { 'file_path' => "/alt#{i}.jpg" } } }
    )

    expect(candidates.size).to be <= described_class::MAX_CANDIDATES
  end

  # The ids are exact but most entries do not have usable ones. Searching by title is what
  # gives the picker anything to say about the rest.
  describe 'searching by title' do
    let(:entry) { create(:entry, list: list, name: 'Fantasmas', year: 2024, tmdb: nil, imdb: nil, position: 1) }

    before do
      allow(tmdb).to receive(:fetch_omdb_poster_url).and_return(nil)
      allow(tmdb).to receive(:search_movie).and_return(
        { 'results' => [{ 'poster_path' => '/found.jpg', 'title' => 'Fantasmas', 'release_date' => '2024-06-07' }] }
      )
    end

    it 'finds a poster for an entry carrying no ids at all' do
      expect(candidates.map { |c| c[:url] }).to include('https://image.tmdb.org/t/p/w500/found.jpg')
    end

    it 'searches on the name and the year' do
      candidates

      expect(tmdb).to have_received(:search_movie).with('Fantasmas', year: 2024)
    end

    # A title search can land on a different film of the same name, and you should be able
    # to see which one before you pick it.
    it 'says which title and year the result matched' do
      expect(sources).to include('TMDB search: Fantasmas (2024)')
    end

    it 'offers OMDB search results too' do
      allow(OmdbApi).to receive(:search_with_posters)
        .and_return([{ poster: 'https://omdb.example/found.jpg', title: 'Fantasmas', year: '2024' }])

      expect(candidates).to include({ url: 'https://omdb.example/found.jpg', source: 'OMDB search: Fantasmas (2024)' })
    end

    # A search for an unusual title returns a lot of things that merely share a word with
    # it. In the picker those look exactly as authoritative as the right answer.
    it 'drops a match that only shares a word with the title' do
      allow(tmdb).to receive(:search_movie).and_return(
        { 'results' => [{ 'poster_path' => '/wrong.jpg', 'title' => 'Atrapa Fantasmas', 'release_date' => '2024-01-01' },
                        { 'poster_path' => '/right.jpg', 'title' => 'Fantasmas', 'release_date' => '2024-06-07' }] }
      )

      expect(candidates.map { |c| c[:url] }).to contain_exactly('https://image.tmdb.org/t/p/w500/right.jpg')
    end

    it 'drops an OMDB match that only shares a word with the title' do
      allow(OmdbApi).to receive(:search_with_posters)
        .and_return([{ poster: 'https://omdb.example/wrong.jpg', title: 'Sith Wars: Fantasmas Dos Sith', year: '2024' }])

      expect(sources).not_to include(a_string_starting_with('OMDB search'))
    end

    # The title asked for is often the start of a longer one, and that is a real answer.
    it 'keeps a match that leads with the title' do
      allow(tmdb).to receive(:search_movie).and_return(
        { 'results' => [{ 'poster_path' => '/sequel.jpg', 'title' => 'Fantasmas: The Reckoning', 'release_date' => '2025-01-01' }] }
      )

      expect(sources).to include('TMDB search: Fantasmas: The Reckoning (2025)')
    end

    # TMDB and OMDB disagree about punctuation and case constantly.
    it 'ignores punctuation and case when deciding whether a match is plausible' do
      entry.update!(name: 'WALL-E')
      allow(tmdb).to receive(:search_movie).and_return(
        { 'results' => [{ 'poster_path' => '/walle.jpg', 'title' => 'WALL·E', 'release_date' => '2008-06-27' }] }
      )

      expect(candidates.map { |c| c[:url] }).to include('https://image.tmdb.org/t/p/w500/walle.jpg')
    end

    it 'returns nothing rather than raising when no source has anything' do
      allow(tmdb).to receive(:search_movie).and_return({ 'results' => [] })

      expect(candidates).to eq([])
    end
  end

  # An episode's tmdb id is the show's, so every episode of a series used to be offered the
  # same series poster. The still is the art that actually belongs to this one.
  describe 'an episode' do
    let(:entry) do
      create(:entry, list: list, name: 'The Race', series: 'Seinfeld', media: 'episode',
                     season: 6, episode: 10, year: 1994, tmdb: '1400', imdb: nil, position: 1)
    end

    before do
      allow(tmdb).to receive(:fetch_omdb_poster_url).and_return(nil)
      allow(tmdb).to receive(:fetch_episode).and_return({ 'still_path' => '/still.jpg' })
      allow(tmdb).to receive(:fetch_season).and_return({ 'poster_path' => '/season6.jpg' })
    end

    it 'offers the still for this episode ahead of everything else' do
      expect(candidates.first).to eq(
        { url: 'https://image.tmdb.org/t/p/w500/still.jpg', source: 'TMDB still: S6E10' }
      )
    end

    it 'offers the season poster as well' do
      expect(sources).to include('TMDB: season 6')
    end

    it 'asks for the still by season and episode' do
      candidates

      expect(tmdb).to have_received(:fetch_episode).with('1400', 6, 10)
    end

    # Only 189 of the 1,595 episodes carry a tmdb id; nearly all of them carry the show's
    # name, so the show can be looked up instead.
    it 'finds the show by name when the episode has no tmdb id of its own' do
      entry.update!(tmdb: nil)
      allow(tmdb).to receive(:search_tv).and_return({ 'results' => [{ 'id' => 1400 }] })

      described_class.new(entry, tmdb: tmdb, image_search: image_search).call

      expect(tmdb).to have_received(:search_tv).with('Seinfeld')
      expect(tmdb).to have_received(:fetch_episode).with('1400', 6, 10)
    end

    it 'searches under the show name, not the episode title' do
      allow(tmdb).to receive(:search_tv).and_return({ 'results' => [] })

      described_class.new(entry, tmdb: tmdb, image_search: image_search).call

      expect(tmdb).to have_received(:search_tv).with('Seinfeld', year: 1994)
    end
  end

  describe 'the open web' do
    it 'offers what the image search found, labelled by where it came from' do
      allow(image_search).to receive(:call)
        .and_return([{ url: 'https://fanart.example/a.jpg', host: 'fanart.example', width: 600, height: 900 }])

      expect(candidates).to include({ url: 'https://fanart.example/a.jpg', source: 'Web: fanart.example' })
    end

    it 'asks for a poster by name and year' do
      candidates

      expect(image_search).to have_received(:call).with('The Avengers 2012 poster', portrait_only: true)
    end

    # A still is landscape, so the portrait filter that keeps banners out of a poster
    # search would throw away every correct answer here.
    it 'does not insist on portrait art for an episode' do
      episode = create(:entry, list: list, name: 'The Race', series: 'Seinfeld', media: 'episode',
                               season: 6, episode: 10, tmdb: nil, imdb: nil, position: 1)

      described_class.new(episode, tmdb: tmdb, image_search: image_search).call

      expect(image_search).to have_received(:call).with('Seinfeld s6e10 The Race', portrait_only: false)
    end
  end

  describe 'resilience' do
    it 'keeps the other sources when the TMDB image call fails' do
      allow(tmdb).to receive(:fetch_images).and_raise(TmdbService::RequestError, 'boom')

      expect(sources).to include('TMDB', 'OMDB')
    end

    it 'keeps going when the imdb lookup fails' do
      allow(tmdb).to receive(:find_by_imdb_id).and_raise(TmdbService::RequestError, 'boom')

      expect(sources).to include('OMDB')
    end

    it 'keeps going when the title search fails' do
      allow(tmdb).to receive(:search_movie).and_raise(TmdbService::RequestError, 'boom')

      expect(sources).to include('TMDB', 'OMDB')
    end

    it 'keeps going when OMDB search fails' do
      allow(OmdbApi).to receive(:search_with_posters).and_raise(StandardError, 'boom')

      expect(sources).to include('TMDB', 'OMDB')
    end
  end

  describe 'recent posters from the same list' do
    it 'offers posters attached to the preceding entries' do
      previous = create(:entry, list: list, name: 'Earlier', position: 2)
      previous.poster.attach(
        io: StringIO.new('fake-image-bytes'), filename: 'earlier.jpg', content_type: 'image/jpeg'
      )

      result = described_class.new(entry, tmdb: tmdb, image_search: image_search,
                                          url_builder: ->(_p) { 'https://host/earlier.jpg' }).call

      expect(result).to include({ url: 'https://host/earlier.jpg', source: 'Recent: Earlier' })
    end
  end
end
