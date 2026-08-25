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

  describe 'classifying a pasted URL' do
    it 'recognises a Drive share link' do
      expect(described_class.classify_url('https://drive.google.com/file/d/1abc/view')).to eq(['google-drive', '1abc'])
    end

    it 'recognises both mega forms' do
      expect(described_class.classify_url('https://mega.nz/embed/KEY#frag')).to eq(['mega', 'KEY#frag'])
      expect(described_class.classify_url('https://mega.nz/file/KEY#frag')).to eq(['mega', 'KEY#frag'])
    end

    it 'passes an unknown host through the custom provider' do
      expect(described_class.classify_url('https://gotaku1.com/x?id=1')).to eq(['custom', 'https://gotaku1.com/x?id=1'])
    end

    it 'declines imdb-keyed provider URLs, which carry no key of their own' do
      expect(described_class.classify_url('https://vidsrc.cc/v3/embed/movie/tt1')).to eq([nil, nil])
    end
  end
end
