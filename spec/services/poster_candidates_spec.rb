require 'rails_helper'

RSpec.describe PosterCandidates do
  let(:list) { create(:list) }
  let(:entry) { create(:entry, list: list, tmdb: '299536', imdb: 'tt4154756', position: 3) }

  let(:tmdb) do
    instance_double(TmdbService,
                    fetch_poster_url: 'https://image.tmdb.org/t/p/w500/primary.jpg',
                    fetch_images: { 'posters' => [{ 'file_path' => '/alt1.jpg' }, { 'file_path' => '/alt2.jpg' }] },
                    find_by_imdb_id: { 'movie_results' => [{ 'poster_path' => '/via-imdb.jpg' }] },
                    fetch_omdb_poster_url: 'https://omdb.example/poster.jpg')
  end

  subject(:candidates) { described_class.new(entry, tmdb: tmdb).call }

  it 'offers the TMDB poster first, then alternates' do
    expect(candidates.first).to eq({ url: 'https://image.tmdb.org/t/p/w500/primary.jpg', source: 'TMDB' })
    expect(candidates.map { |c| c[:url] }).to include('https://image.tmdb.org/t/p/w500/alt1.jpg')
  end

  it 'includes art found via the imdb id and OMDB' do
    sources = candidates.map { |c| c[:source] }

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

    described_class.new(entry, tmdb: tmdb).call

    expect(tmdb).to have_received(:fetch_poster_url).with('299536', 'tv')
  end

  describe 'resilience' do
    it 'keeps the other sources when the TMDB image call fails' do
      allow(tmdb).to receive(:fetch_images).and_raise(TmdbService::RequestError, 'boom')

      expect(candidates.map { |c| c[:source] }).to include('TMDB', 'OMDB')
    end

    it 'keeps going when the imdb lookup fails' do
      allow(tmdb).to receive(:find_by_imdb_id).and_raise(TmdbService::RequestError, 'boom')

      expect(candidates.map { |c| c[:source] }).to include('OMDB')
    end

    it 'returns nothing rather than raising for an entry with no ids' do
      bare = create(:entry, list: list, tmdb: nil, imdb: nil, series_imdb: nil, position: 1)
      allow(tmdb).to receive(:fetch_omdb_poster_url).and_return(nil)

      expect(described_class.new(bare, tmdb: tmdb).call).to eq([])
    end
  end

  describe 'recent posters from the same list' do
    it 'offers posters attached to the preceding entries' do
      previous = create(:entry, list: list, name: 'Earlier', position: 2)
      previous.poster.attach(
        io: StringIO.new('fake-image-bytes'), filename: 'earlier.jpg', content_type: 'image/jpeg'
      )

      result = described_class.new(entry, tmdb: tmdb, url_builder: ->(_p) { 'https://host/earlier.jpg' }).call

      expect(result).to include({ url: 'https://host/earlier.jpg', source: 'Recent: Earlier' })
    end
  end
end
