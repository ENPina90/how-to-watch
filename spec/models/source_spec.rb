require 'rails_helper'

RSpec.describe Source do
  def source(templates, kind: 'imdb', autoplay_param: nil)
    described_class.create!(name: "Test #{SecureRandom.hex(4)}", kind: kind,
                            templates: templates, autoplay_param: autoplay_param)
  end

  let(:list) { create(:list) }

  describe '#url_for' do
    it 'substitutes the entry ids into the template' do
      provider = source({ 'movie' => 'https://p.test/movie/%{imdb}' })
      entry = build(:entry, list: list, media: 'movie', imdb: 'tt0848228')

      expect(provider.url_for(entry)).to eq('https://p.test/movie/tt0848228')
    end

    it 'takes season and episode from the supplied subentry' do
      provider = source({ 'series' => 'https://p.test/tv/%{series_imdb}/%{season}/%{episode}' })
      entry = create(:entry, list: list, media: 'series', imdb: 'tt0903747')
      subentry = Subentry.create!(entry: entry, season: '2', episode: '5', name: 'Ep')

      expect(provider.url_for(entry, subentry: subentry)).to eq('https://p.test/tv/tt0903747/2/5')
    end

    it 'falls back to the default template for an unknown media key' do
      provider = source({ 'default' => 'https://p.test/%{source_key}' }, kind: 'direct')
      entry = build(:entry, list: list, media: 'fanedit', source_key: 'abc123')

      expect(provider.url_for(entry)).to eq('https://p.test/abc123')
    end

    it 'appends the autoplay parameter when the provider defines one' do
      provider = source({ 'movie' => 'https://p.test/movie/%{imdb}' }, autoplay_param: 'autoplay')
      entry = build(:entry, list: list, media: 'movie', imdb: 'tt1')

      expect(provider.url_for(entry, autoplay: true)).to eq('https://p.test/movie/tt1?autoplay=1')
    end
  end

  describe 'refusing to build a half-substituted URL' do
    # A URL with a hole in it is worse than no URL: Entry#embed_url only reaches its
    # legacy fallback when this returns blank, so a truncated string gets served as if
    # it were playable.
    it 'returns nil when the entry has no imdb id' do
      provider = source({ 'movie' => 'https://p.test/movie/%{imdb}' })
      entry = build(:entry, list: list, media: 'movie', imdb: nil)

      expect(provider.url_for(entry)).to be_nil
    end

    it 'returns nil for a series with no episode resolved' do
      provider = source({ 'series' => 'https://p.test/tv/%{series_imdb}/%{season}/%{episode}' })
      entry = build(:entry, list: list, media: 'series', imdb: 'tt1', season: nil, episode: nil)

      expect(provider.url_for(entry, subentry: nil)).to be_nil
    end

    it 'returns nil for a direct provider with no source key' do
      provider = source({ 'default' => 'https://p.test/%{source_key}' }, kind: 'direct')
      entry = build(:entry, list: list, media: 'fanedit', source_key: nil)

      expect(provider.url_for(entry)).to be_nil
    end

    it 'returns nil when there is no template for the media type' do
      provider = source({ 'movie' => 'https://p.test/movie/%{imdb}' })
      entry = build(:entry, list: list, media: 'series', imdb: 'tt1')

      expect(provider.url_for(entry)).to be_nil
    end
  end

  describe 'the entry falling back' do
    it 'uses the stored legacy source when the provider cannot build a URL' do
      provider = source({ 'movie' => 'https://p.test/movie/%{imdb}' })
      entry = create(:entry, list: list, media: 'movie', imdb: nil,
                             source: 'https://legacy.test/stored', provider: provider)

      expect(entry.embed_url).to eq('https://legacy.test/stored?autoplay=0')
    end
  end
end
