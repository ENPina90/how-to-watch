require 'rails_helper'

RSpec.describe Source do
  def source(templates, kind: 'imdb', autoplay_param: nil, slug: nil)
    described_class.create!(name: "Test #{SecureRandom.hex(4)}", kind: kind, slug: slug,
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

    # Without enablejsapi the embed answers no handshake, and the adapter hears nothing.
    it 'asks a YouTube embed to report, and resumes it with its own parameter' do
      provider = source({ 'default' => 'https://www.youtube.com/embed/%{source_key}' },
                        kind: 'direct', autoplay_param: 'autoplay', slug: 'youtube')
      entry = build(:entry, list: list, media: 'fanedit', source_key: 'rz950l805x4')

      expect(provider.url_for(entry, autoplay: true, start_at: 742.5))
        .to eq('https://www.youtube.com/embed/rz950l805x4?enablejsapi=1&autoplay=1&start=743')
    end

    it 'adds no player parameters for a provider whose adapter needs none' do
      provider = source({ 'movie' => 'https://p.test/movie/%{imdb}' }, slug: 'vidsrc2')
      entry = build(:entry, list: list, media: 'movie', imdb: 'tt1')

      expect(provider.url_for(entry)).to eq('https://p.test/movie/tt1')
    end

    # Behind the `#` it would be part of the fragment: never sent to the provider, and on a
    # MEGA link read as part of the decryption key.
    it 'puts a query parameter before a fragment rather than inside it' do
      provider = source({ 'default' => 'https://p.test/v/%{source_key}' }, kind: 'direct', autoplay_param: 'autoplay')
      entry = build(:entry, list: list, media: 'fanedit', source_key: 'abc#frag')

      expect(provider.url_for(entry, autoplay: true)).to eq('https://p.test/v/abc?autoplay=1#frag')
    end
  end

  # MEGA takes autoplay as a flag inside the key fragment, not as a query parameter.
  describe 'autoplay on MEGA' do
    # The catalog may already have created the row at boot, and slugs are unique.
    let(:mega) do
      described_class.find_or_initialize_by(slug: 'mega').tap do |source|
        source.update!(name: 'MEGA', kind: 'direct', autoplay_param: nil,
                       templates: { 'default' => 'https://mega.nz/embed/%{source_key}' })
      end
    end

    def entry_keyed(key) = build(:entry, list: list, media: 'fanedit', source_key: key)

    it 'adds the autoplay flag to the key fragment' do
      expect(mega.url_for(entry_keyed('ID#KEY'), autoplay: true)).to eq('https://mega.nz/embed/ID#KEY!1a')
    end

    it 'leaves the link alone when autoplay is off' do
      expect(mega.url_for(entry_keyed('ID#KEY'))).to eq('https://mega.nz/embed/ID#KEY')
    end

    # MEGA keeps only the first run of options, so a second `!1a` would be ignored.
    it 'joins options already pasted onto the key' do
      expect(mega.url_for(entry_keyed('ID#KEY!1m'), autoplay: true)).to eq('https://mega.nz/embed/ID#KEY!1m1a')
    end

    it 'does not add the flag twice' do
      expect(mega.url_for(entry_keyed('ID#KEY!1a'), autoplay: true)).to eq('https://mega.nz/embed/ID#KEY!1a')
    end
  end

  # Whether the page can start a player at all. Asked as a capability rather than read off
  # `autoplay_param`, because the column is only one of the two routes there.
  describe '#autoplays?' do
    it 'is true for a provider with an autoplay query parameter' do
      expect(source({ 'movie' => 'https://p.test/%{imdb}' }, autoplay_param: 'autoplay')).to be_autoplays
    end

    # The case the old check got backwards: no parameter, and it autoplays fine.
    it 'is true for MEGA, which takes the flag in the key fragment' do
      mega = described_class.find_or_initialize_by(slug: 'mega').tap do |s|
        s.update!(name: 'MEGA', kind: 'direct', autoplay_param: nil,
                  templates: { 'default' => 'https://mega.nz/embed/%{source_key}' })
      end

      expect(mega.autoplay_param).to be_blank
      expect(mega).to be_autoplays
    end

    it 'is false for a provider with neither route' do
      drive = source({ 'default' => 'https://drive.google.com/file/d/%{source_key}/preview' },
                     kind: 'direct', slug: 'google-drive')

      expect(drive).not_to be_autoplays
    end
  end

  # The other half of that option run. MEGA answers no message from the page, so where it
  # starts is decided as the frame is written or not at all -- and unlike every other
  # resumable provider it reads the position from behind the `#` rather than from the query.
  describe 'the start position on MEGA' do
    let(:mega) do
      described_class.find_or_initialize_by(slug: 'mega').tap do |source|
        source.update!(name: 'MEGA', kind: 'direct', autoplay_param: nil,
                       templates: { 'default' => 'https://mega.nz/embed/%{source_key}' })
      end
    end

    def entry_keyed(key) = build(:entry, list: list, media: 'fanedit', source_key: key)

    it 'counts as resumable even with no query parameter to carry a position' do
      expect(mega).to be_resumable
    end

    it 'writes the position into the key fragment' do
      expect(mega.url_for(entry_keyed('ID#KEY'), start_at: 900))
        .to eq('https://mega.nz/embed/ID#KEY!900s')
    end

    # Ahead of the rest of the run, which is the order MEGA's own embed dialog writes.
    it 'puts the position in front of the flags already in the run' do
      expect(mega.url_for(entry_keyed('ID#KEY'), autoplay: true, start_at: 900))
        .to eq('https://mega.nz/embed/ID#KEY!900s1a')
    end

    it 'rounds a fractional position, as the query-parameter providers do' do
      expect(mega.url_for(entry_keyed('ID#KEY'), start_at: 742.5))
        .to eq('https://mega.nz/embed/ID#KEY!743s')
    end

    # The bug this is all for. A key pasted out of somebody's browser carries the position
    # they were sitting at, and MEGA obeys it on every load -- so the entry played from
    # 1:40 for ever, and a reloaded frame looked like it was resuming from the page load.
    it 'replaces a position already pasted onto the key rather than joining it' do
      expect(mega.url_for(entry_keyed('ID#KEY!100s1a'), autoplay: true, start_at: 900))
        .to eq('https://mega.nz/embed/ID#KEY!900s1a')
    end

    it 'takes a pasted position out when there is no position to play from' do
      expect(mega.url_for(entry_keyed('ID#KEY!100s'), autoplay: true))
        .to eq('https://mega.nz/embed/ID#KEY!1a')
    end

    # Nothing left in the run means nothing to write: no bare `!` on the end.
    it 'leaves no empty option run behind' do
      expect(mega.url_for(entry_keyed('ID#KEY!100s'))).to eq('https://mega.nz/embed/ID#KEY')
    end

    it 'leaves a link with no key fragment alone' do
      expect(mega.url_for(entry_keyed('ID'), start_at: 900)).to eq('https://mega.nz/embed/ID')
    end

    # Drive and the catch-all have neither route to a position. The offset is computed for
    # them all the same -- the cable schedule does not know what it is talking to -- so
    # dropping it silently has to stay the behaviour rather than becoming an error.
    it 'still drops the position for a provider with no way to take one' do
      drive = source({ 'default' => 'https://drive.test/file/%{source_key}/preview' },
                     kind: 'direct', slug: 'google-drive')

      expect(drive).not_to be_resumable
      expect(drive.url_for(entry_keyed('ABC'), start_at: 900))
        .to eq('https://drive.test/file/ABC/preview')
    end
  end

  # Subtitles can only be decided as the frame is written: the player's own message handler
  # ignores everything that is not play/pause/mute/unmute/seek, so there is no asking it
  # afterwards. /cable is the page that wants none -- see docs/guides/VIDSRC.md §3.
  describe 'turning the subtitles off' do
    # The adapter is looked up from the slug, so a vidsrc-backed provider is one wearing a
    # vidsrc slug -- there is no column to set.
    def vidsrc(template)
      source({ 'movie' => template }, slug: 'vidsrc2', autoplay_param: 'autoplay')
    end

    let(:entry) { build(:entry, list: list, media: 'movie', imdb: 'tt1') }

    it 'leaves the subtitle language in by default' do
      provider = vidsrc('https://p.test/movie?imdb=%{imdb}&ds_lang=en')

      expect(provider.url_for(entry)).to include('ds_lang=en')
    end

    # Taken out rather than set to an off value: ds_lang names a language, and the only way
    # to ask for none is not to name one.
    it 'takes it out when the page does not want subtitles' do
      provider = vidsrc('https://p.test/movie?imdb=%{imdb}&ds_lang=en')

      expect(provider.url_for(entry, subtitles: false)).to eq('https://p.test/movie?imdb=tt1&autoplay=0')
    end

    # The parameter can sit anywhere in the query, and each position drops a different
    # separator with it -- which is why the query is rebuilt rather than pattern-matched.
    it 'takes it out from the middle of the query' do
      provider = vidsrc('https://p.test/movie?ds_lang=en&imdb=%{imdb}&x=1')

      expect(provider.url_for(entry, subtitles: false)).to eq('https://p.test/movie?imdb=tt1&x=1&autoplay=0')
    end

    it 'leaves a template that names no subtitle language alone' do
      provider = vidsrc('https://p.test/movie?imdb=%{imdb}')

      expect(provider.url_for(entry, subtitles: false)).to eq('https://p.test/movie?imdb=tt1&autoplay=0')
    end

    it 'drops the query entirely when the subtitle language was all of it' do
      provider = vidsrc('https://p.test/movie/%{imdb}?ds_lang=en')

      expect(provider.url_for(entry, subtitles: false)).to eq('https://p.test/movie/tt1?autoplay=0')
    end

    # A provider with no adapter has no player to ask, so there is no parameter to name.
    it 'leaves a provider with no adapter alone' do
      provider = source({ 'movie' => 'https://p.test/movie?imdb=%{imdb}&ds_lang=en' })

      expect(provider.url_for(entry, subtitles: false)).to include('ds_lang=en')
    end

    it 'still resumes where it was asked to' do
      provider = vidsrc('https://p.test/movie?imdb=%{imdb}&ds_lang=en')

      url = provider.url_for(entry, subtitles: false, start_at: 300, autoplay: true)

      expect(url).to eq('https://p.test/movie?imdb=tt1&autoplay=1&startAt=300')
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
