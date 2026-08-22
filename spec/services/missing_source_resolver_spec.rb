require 'rails_helper'

RSpec.describe MissingSourceResolver do
  let(:list) { create(:list) }
  let(:tmdb) { instance_double(TmdbService) }

  def resolve(entry) = described_class.new(entry, tmdb: tmdb).call

  describe 'an imdb id sitting in the legacy URL' do
    it 'takes the id straight from the URL' do
      allow(OmdbApi).to receive(:get_movie).with('tt0142235')
                                           .and_return({ 'Title' => 'Dragon Ball Z: Dead Zone', 'Year' => '1989' })
      entry = create(:entry, list: list, imdb: nil, name: 'Dead Zone', year: 1989,
                             source: 'https://v2.vidsrc.me/embed/tt0142235')

      result = resolve(entry)

      expect(result[:strategy]).to eq(:imdb_in_url)
      expect(result[:imdb]).to eq('tt0142235')
      expect(result[:confidence]).to eq(:exact)
      expect(result[:note]).to include('Dragon Ball Z: Dead Zone')
    end

    it 'still proposes the id when OMDB cannot confirm it' do
      allow(OmdbApi).to receive(:get_movie).and_return(nil)
      entry = create(:entry, list: list, imdb: nil, source: 'https://v2.vidsrc.me/embed/tt9999999')

      expect(resolve(entry)[:imdb]).to eq('tt9999999')
    end
  end

  describe 'an entry that knows its TMDB id' do
    it 'asks TMDB for the imdb id' do
      allow(tmdb).to receive(:fetch_imdb_id).with('1726', 'movie').and_return('tt0371746')
      entry = create(:entry, list: list, imdb: nil, tmdb: '1726', name: 'Iron Man (I)',
                             source: 'https://drive.google.com/file/d/1ob3XHNP/view')

      result = resolve(entry)

      expect(result[:strategy]).to eq(:imdb_from_tmdb)
      expect(result[:imdb]).to eq('tt0371746')
      expect(result[:confidence]).to eq(:exact)
    end

    it 'uses the tv endpoint for a series' do
      allow(tmdb).to receive(:fetch_imdb_id).with('1396', 'show').and_return('tt0903747')
      entry = create(:entry, list: list, imdb: nil, tmdb: '1396', media: 'series',
                             source: 'https://v2.vidsrc.me/embed/')

      expect(resolve(entry)[:imdb]).to eq('tt0903747')
    end
  end

  describe 'a fan edit hosted on a file host' do
    before { Source.create!(name: 'Google Drive', slug: 'google-drive', kind: 'direct', templates: { 'default' => 'x/%{source_key}' }) }

    it 'proposes a direct provider and key rather than an imdb id' do
      entry = create(:entry, list: list, imdb: nil, tmdb: nil, name: 'Episode IV - A New Hope: Revisited',
                             year: 1977, source: 'https://drive.google.com/file/d/1abcDEF/view')

      result = resolve(entry)

      expect(result[:strategy]).to eq(:direct_source)
      expect(result[:provider].slug).to eq('google-drive')
      expect(result[:source_key]).to eq('1abcDEF')
      expect(result[:imdb]).to be_nil
    end

    it 'never runs a title search for one' do
      # This is the safety rule: searching "A New Hope: Revisited" matches the official
      # film, and applying that would swap the fan edit for the studio release.
      allow(OmdbApi).to receive(:search_by_title)
      entry = create(:entry, list: list, imdb: nil, name: 'Episode IV - A New Hope: Revisited',
                             source: 'https://drive.google.com/file/d/1abcDEF/view')

      resolve(entry)

      expect(OmdbApi).not_to have_received(:search_by_title)
    end

    it 'passes an unrecognised host through the custom provider' do
      Source.create!(name: 'Custom', slug: 'custom', kind: 'direct', templates: { 'default' => '%{source_key}' })
      entry = create(:entry, list: list, imdb: nil, source: 'https://gotaku1.com/streaming.php?id=MTg')

      result = resolve(entry)

      expect(result[:provider].slug).to eq('custom')
      expect(result[:source_key]).to eq('https://gotaku1.com/streaming.php?id=MTg')
    end
  end

  describe 'falling back to a title search' do
    let(:entry) do
      create(:entry, list: list, imdb: nil, tmdb: nil, media: 'series',
                     name: 'Faulty towers', year: 2008, source: 'https://v2.vidsrc.me/embed/')
    end

    it 'offers candidates but marks them for review' do
      allow(OmdbApi).to receive(:search_by_title).and_return(%w[tt0072500])
      allow(OmdbApi).to receive(:get_movie).with('tt0072500')
                                           .and_return({ 'Title' => 'Fawlty Towers', 'Year' => '1975' })
      allow(tmdb).to receive(:search_tv).and_return({ 'results' => [] })

      result = resolve(entry)

      expect(result[:strategy]).to eq(:title_search)
      expect(result[:imdb]).to eq('tt0072500')
      expect(result[:confidence]).to eq(:review)
    end

    it 'reports honestly when nothing matches' do
      allow(OmdbApi).to receive(:search_by_title).and_return([])
      allow(tmdb).to receive(:search_tv).and_return({ 'results' => [] })

      result = resolve(entry)

      expect(result[:imdb]).to be_nil
      expect(result[:note]).to eq('no candidates found')
    end

    it 'survives OMDB raising' do
      allow(OmdbApi).to receive(:search_by_title).and_raise(StandardError, 'boom')
      allow(tmdb).to receive(:search_tv).and_return({ 'results' => [] })

      expect { resolve(entry) }.not_to raise_error
    end
  end

  it 'reports nothing to work from when there is no legacy URL' do
    entry = create(:entry, list: list, imdb: nil, source: nil, source_two: nil)

    expect(resolve(entry)[:strategy]).to eq(:none)
  end
end
