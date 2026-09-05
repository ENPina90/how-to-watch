# frozen_string_literal: true

require 'rails_helper'

# The only endpoint in the chain that actually knows. Everything in front of it -- the
# embed, the shell, vs_src.php -- answers 200 for a title VidSrc has never held.
RSpec.describe VidsrcAvailability do
  let(:list) { create(:list) }

  def answering(body, status: 200)
    stub_request(:get, /data\.vidsrcme\.ru\/api\.php/).to_return(status: status, body: body)
  end

  describe 'reading the answer' do
    it 'calls a title with a file available' do
      answering({ status_code: '200', data: { title: 'Gladiator' } }.to_json)
      entry = create(:entry, list: list, imdb: 'tt0172495')

      expect(described_class.new.for_entry(entry).state).to eq(:available)
    end

    it 'calls a 404 missing' do
      answering({ status_code: 404 }.to_json)
      entry = create(:entry, list: list, imdb: 'tt0177242')

      expect(described_class.new.for_entry(entry)).to be_missing
    end

    # The endpoint quotes 200 and does not quote 404. Reading it strictly would make every
    # available title look like a failure.
    it 'does not mind that the API quotes one code and not the other' do
      answering('{"status_code":"200","data":{}}')
      entry = create(:entry, list: list, imdb: 'tt0172495')

      expect(described_class.new.for_entry(entry).state).to eq(:available)
    end
  end

  # :unknown is the whole reason there are three states. A sweep that read "no answer" as
  # "missing" would condemn every entry the moment the host rotated.
  describe 'when it cannot get an answer' do
    it 'is unknown, never missing, when the request fails' do
      stub_request(:get, /data\.vidsrcme\.ru/).to_raise(Errno::ECONNREFUSED)
      entry = create(:entry, list: list, imdb: 'tt0172495')

      expect(described_class.new.for_entry(entry)).to be_unknown
    end

    it 'is unknown, never missing, when the answer is not JSON' do
      answering('<html>blocked</html>')
      entry = create(:entry, list: list, imdb: 'tt0172495')

      expect(described_class.new.for_entry(entry)).to be_unknown
    end

    it 'says it is unreachable so a sweep can stop before judging anything' do
      stub_request(:get, /data\.vidsrcme\.ru/).to_return(status: 502, body: '')

      expect(described_class.new.reachable?).to be(false)
    end
  end

  describe 'what it asks about' do
    before { answering({ status_code: 404 }.to_json) }

    it 'asks for a film by its own imdb id' do
      entry = create(:entry, list: list, imdb: 'tt0172495', media: 'movie')

      described_class.new.for_entry(entry)

      expect(a_request(:get, /api\.php/).with(query: hash_including('type' => 'movie', 'imdb' => 'tt0172495')))
        .to have_been_made
    end

    # A show is never asked about as a show: what plays is one episode, and that is what
    # VidSrc either holds or does not.
    it 'asks for a show by the episode it would play' do
      entry = create(:entry, list: list, media: 'series', imdb: 'tt0098904', series_imdb: 'tt0098904')
      Subentry.create!(entry: entry, season: 6, episode: 10, name: 'The Race')

      described_class.new.for_entry(entry)

      expect(a_request(:get, /api\.php/).with(query: hash_including('type' => 'tv', 'season' => '6', 'episode' => '10')))
        .to have_been_made
    end

    it 'has nothing to ask when the entry carries no id' do
      entry = create(:entry, list: list, imdb: nil, media: 'movie')

      expect(described_class.new.for_entry(entry)).to be_unknown
      expect(a_request(:get, /api\.php/)).not_to have_been_made
    end
  end
end
