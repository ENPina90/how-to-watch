# frozen_string_literal: true

require 'rails_helper'

# An embed that will not play looks exactly like one that will: same 200, same shell. The
# only difference is a file VidSrc either holds or does not, so the audit has to go and ask
# -- and has to be very careful about what it does when it cannot.
RSpec.describe EmbedAvailabilityAudit do
  let(:list) { create(:list) }
  let!(:vidsrc) do
    Source.create!(name: 'Framerelay', slug: 'framerelay', kind: 'imdb', active: true, position: 1,
                   templates: { 'movie' => 'https://framerelay.dev/embed/movie?imdb=%{imdb}',
                                'series' => 'https://framerelay.dev/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}',
                                'episode' => 'https://framerelay.dev/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}' })
  end

  let(:catalog) { instance_double(VidsrcCatalog, warm!: true, movie?: true, episode?: true) }
  let(:availability) { instance_double(VidsrcAvailability, reachable?: true) }

  def audit(scope: Entry.all)
    described_class.new(scope: scope, catalog: catalog, availability: availability).call
  end

  # The real lookup resolution, so the spec cannot drift from what the entry would ask for.
  def real_lookup(entry) = VidsrcAvailability.new.lookup_for(entry)

  def answering(entry, state, detail = nil)
    allow(availability).to receive(:lookup_for).with(entry).and_return(real_lookup(entry))
    allow(availability).to receive(:for_entry).with(entry)
      .and_return(VidsrcAvailability::Result.new(state: state, detail: detail))
  end

  before do
    allow(availability).to receive(:lookup_for) { |entry| real_lookup(entry) }
    allow(availability).to receive(:for_entry).and_return(VidsrcAvailability::Result.new(state: :available))
  end

  it 'reports an entry the API says there is no file for' do
    entry = create(:entry, list: list, name: 'Sonnen alle', imdb: 'tt0177242')
    allow(catalog).to receive(:movie?).and_return(false)
    answering(entry, :missing, 'VidSrc has no file for it')

    result = audit

    expect(result.missing.map(&:entry)).to eq([entry])
    expect(result.missing.first.reason).to eq('VidSrc has no file for it')
  end

  # The dumps are a screen, not a verdict: measured, one in eight they call missing is
  # actually playable. Reporting straight off them would be a fifth of the list wrong.
  it 'does not report an entry the dumps doubted but the API has' do
    entry = create(:entry, list: list, name: 'The Gathering', imdb: 'tt0106336')
    allow(catalog).to receive(:movie?).and_return(false)
    answering(entry, :available)

    result = audit

    expect(result.suspected).to eq(1)
    expect(result.missing).to be_empty
  end

  it 'asks about nothing the dumps already vouched for' do
    create(:entry, list: list, name: 'Gladiator', imdb: 'tt0172495')
    allow(catalog).to receive(:movie?).and_return(true)

    result = audit

    expect(availability).not_to have_received(:for_entry)
    expect(result.suspected).to be_zero
    expect(result.checked).to eq(1)
  end

  # An unanswered question is not a verdict either.
  it 'counts an entry the API would not answer for, and does not report it' do
    entry = create(:entry, list: list, name: 'Quiet one', imdb: 'tt0000001')
    allow(catalog).to receive(:movie?).and_return(false)
    answering(entry, :unknown, 'no answer')

    result = audit

    expect(result.missing).to be_empty
    expect(result.unknown.map(&:entry)).to eq([entry])
  end

  it 'asks about the episode a show would actually play, not the show' do
    entry = create(:entry, list: list, name: 'Seinfeld', media: 'series', imdb: 'tt0098904',
                           series_imdb: 'tt0098904')
    Subentry.create!(entry: entry, season: 6, episode: 10, name: 'The Race')
    allow(catalog).to receive(:episode?).and_return(false)
    answering(entry, :missing, 'VidSrc has no file for it')

    result = audit

    expect(catalog).to have_received(:episode?).with('tt0098904', 6, 10)
    expect(result.missing.first.lookup.season).to eq(6)
  end

  it 'leaves alone an entry that does not play through VidSrc at all' do
    drive = Source.create!(name: 'Drive', slug: 'google-drive', kind: 'direct', active: true, position: 2,
                           templates: { 'movie' => 'https://drive.google.com/file/d/%{source_key}/preview' })
    create(:entry, list: list, name: 'Home video', imdb: nil, source_key: 'abc', provider: drive)

    expect(audit.checked).to be_zero
  end

  # On a VidSrc channel, but with nothing to ask about: a show whose episodes were never
  # imported resolves to no episode at all. sources:audit is where that belongs.
  it 'has nothing to ask about a show with no episode to play' do
    list.update!(provider: vidsrc)
    create(:entry, list: list, name: 'Empty show', media: 'series', imdb: 'tt0098904', series_imdb: nil)

    result = audit

    expect(result.checked).to be_zero
    expect(result.skipped).to eq(1)
  end

  # The failure that matters. If the dumps come back empty or the API goes quiet, every
  # entry looks unplayable, and a sweep that believed that would condemn the catalogue.
  describe 'when it cannot be trusted to run' do
    it 'refuses rather than reporting when the ID dumps cannot be read' do
      allow(catalog).to receive(:warm!).and_raise(VidsrcCatalog::Unavailable, 'empty dump')

      expect { audit }.to raise_error(described_class::CannotCheck, /ID dumps/)
    end

    it 'refuses rather than reporting when the data API is not answering' do
      allow(availability).to receive(:reachable?).and_return(false)

      expect { audit }.to raise_error(described_class::CannotCheck, /not answering/)
    end
  end
end
