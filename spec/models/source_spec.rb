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

  describe 'expiry' do
    def perishable(days)
      described_class.create!(name: "P#{days}", slug: "p#{days.to_s.sub('-', 'm')}", kind: 'imdb',
                              position: 1, valid_until: Date.current + days,
                              templates: { 'movie' => 'https://p.test/%{imdb}' })
    end

    let(:imperishable) do
      described_class.create!(name: 'MEGA', slug: 'mega-x', kind: 'direct', position: 9,
                              templates: { 'default' => 'https://mega.nz/embed/%{source_key}' })
    end

    it 'calls a provider with no date imperishable, and never warns about it' do
      expect(imperishable).not_to be_perishable
      expect(imperishable.expiry_state).to be_nil
      expect(imperishable.days_until_expiry).to be_nil
    end

    it 'is fine well before the date' do
      expect(perishable(200).expiry_state).to eq(:fine)
    end

    it 'is soon once inside the warning window' do
      expect(perishable(10).expiry_state).to eq(:soon)
    end

    # The boundary itself counts as a warning rather than as fine.
    it 'is soon exactly on the edge of the window' do
      expect(perishable(described_class::EXPIRY_WARNING_WINDOW.in_days.to_i).expiry_state).to eq(:soon)
    end

    it 'is soon, not expired, on the day itself' do
      source = perishable(0)

      expect(source.expiry_state).to eq(:soon)
      expect(source).not_to be_expired
    end

    it 'is expired the day after' do
      expect(perishable(-1).expiry_state).to eq(:expired)
    end

    it 'counts days as negative once it is past' do
      expect(perishable(-5).days_until_expiry).to eq(-5)
    end
  end

  describe '#renew!' do
    def source_with(valid_until)
      described_class.create!(name: 'R', slug: 'r', kind: 'imdb', position: 1,
                              valid_until: valid_until,
                              templates: { 'movie' => 'https://r.test/%{imdb}' })
    end

    # Renewing early should not cost the time already paid for, which is how domain
    # registrations actually work.
    it 'extends from the existing date when it has not passed' do
      source = source_with(Date.current + 20)

      source.renew!

      expect(source.valid_until).to eq(Date.current + 20 + 1.year)
    end

    it 'extends from today once it has lapsed' do
      source = source_with(Date.current - 30)

      source.renew!

      expect(source.valid_until).to eq(Date.current + 1.year)
    end

    it 'gives a date to a provider that had none' do
      source = source_with(nil)

      source.renew!

      expect(source.valid_until).to eq(Date.current + 1.year)
    end
  end

  describe '#probe_url' do
    it 'probes an imdb provider with a known film' do
      source = described_class.create!(name: 'P', slug: 'probe', kind: 'imdb', position: 1,
                                       templates: { 'movie' => 'https://p.test/embed/movie?imdb=%{imdb}' })

      expect(source.probe_url).to eq("https://p.test/embed/movie?imdb=#{described_class::PROBE_IMDB}")
    end

    # A direct provider addresses one file by a key, so there is nothing generic to probe
    # it with -- only something already filed under it.
    it 'has nothing to probe a direct provider with until something uses it' do
      source = described_class.create!(name: 'D', slug: 'direct-x', kind: 'direct', position: 9,
                                       templates: { 'default' => 'https://d.test/%{source_key}' })

      expect(source.probe_url).to be_nil
    end

    it 'probes a direct provider with an entry that uses it' do
      source = described_class.create!(name: 'D', slug: 'direct-y', kind: 'direct', position: 9,
                                       templates: { 'default' => 'https://d.test/%{source_key}' })
      user = create(:user)
      create(:entry, list: create(:list, user: user), media: 'movie', provider: source, source_key: 'abc')

      expect(source.probe_url).to eq('https://d.test/abc')
    end
  end
end
