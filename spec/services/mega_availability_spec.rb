# frozen_string_literal: true

require 'rails_helper'

# Whether a MEGA link will play: the file is there, and the key in the link opens it. The
# check it replaced read the embed page's <title>, which MEGA's page does not have, and so
# called every MEGA entry broken.
RSpec.describe MegaAvailability do
  subject(:check) { described_class.new }

  let(:api) { %r{\Ahttps://g\.api\.mega\.co\.nz/cs} }
  let(:list) { create(:list) }
  let!(:mega) do
    Source.find_or_initialize_by(slug: 'mega').tap do |source|
      source.update!(name: 'MEGA', kind: 'direct', active: true,
                     templates: { 'default' => 'https://mega.nz/embed/%{source_key}' })
    end
  end

  # A key and the attributes it opens, built the way MEGA builds them: the 256-bit key's
  # halves XORed into an AES key, and "MEGA{...}" encrypted under it with a zero IV.
  def encode(bytes) = Base64.urlsafe_encode64(bytes, padding: false)

  def key_and_attributes(name: 'Film.mp4')
    raw = Random.bytes(32)
    aes = OpenSSL::Cipher.new('aes-128-cbc').tap do |cipher|
      cipher.encrypt
      cipher.key = (0...16).map { |i| raw.bytes[i] ^ raw.bytes[i + 16] }.pack('C*')
      cipher.iv = "\0" * 16
      cipher.padding = 0
    end
    plain = "MEGA#{{ n: name }.to_json}"
    plain += "\0" * ((16 - (plain.bytesize % 16)) % 16)

    [encode(raw), encode(aes.update(plain) + aes.final)]
  end

  def mega_entry(source_key, name: 'Film')
    create(:entry, list: list, name: name, provider: mega, source_key: source_key, imdb: nil,
                   position: Entry.next_position(list))
  end

  def answer(*answers) = stub_request(:post, api).to_return(status: 200, body: answers.to_json)

  it 'plays when the file is there and the key opens it' do
    key, attributes = key_and_attributes
    answer({ s: 1234, at: attributes })

    expect(check.for_entry(mega_entry("abcdEFGH##{key}"))).to be_available
  end

  it 'reads a key with the player options after it' do
    key, attributes = key_and_attributes
    answer({ s: 1234, at: attributes })

    expect(check.for_entry(mega_entry("abcdEFGH##{key}!100s1a"))).to be_available
  end

  # The player reads only the first 32 bytes of the key; three keys in the library carry a
  # stray character on the end and still open their files.
  it 'plays with a stray character on the end of the key, as the player does' do
    key, attributes = key_and_attributes
    answer({ s: 1234, at: attributes })

    expect(check.for_entry(mega_entry("abcdEFGH##{key}s"))).to be_available
  end

  it 'will not play when MEGA has no file at the link' do
    answer(-9)

    result = check.for_entry(mega_entry('abcdEFGH#key'))

    expect(result).to be_missing
    expect(result.detail).to eq('MEGA has no file at that link')
  end

  it 'will not play when MEGA has taken the file down' do
    answer(-16)

    expect(check.for_entry(mega_entry('abcdEFGH#key')).detail).to eq('MEGA has taken the file down')
  end

  # The case a check of the file alone would call working.
  it 'will not play when the file is there but the key does not open it' do
    _, attributes = key_and_attributes
    other_key, = key_and_attributes
    answer({ s: 1234, at: attributes })

    result = check.for_entry(mega_entry("abcdEFGH##{other_key}"))

    expect(result).to be_missing
    expect(result.detail).to eq('the key in the link does not open the file')
  end

  it 'will not play when the key was cut short' do
    key, attributes = key_and_attributes
    answer({ s: 1234, at: attributes })

    expect(check.for_entry(mega_entry("abcdEFGH##{key[0, 37]}"))).to be_missing
  end

  it 'does not ask about a link with no key at all' do
    result = check.for_entry(mega_entry('abcdEFGH'))

    expect(result).to be_missing
    expect(a_request(:post, api)).not_to have_been_made
  end

  # Asked without `g: 1`, MEGA issues no download link, and so spends none of the transfer
  # quota that stops playback when it runs out.
  it 'asks for the file without asking for a download' do
    request = stub_request(:post, api).with { |req| JSON.parse(req.body) == [{ 'a' => 'g', 'p' => 'abcdEFGH' }] }
                                      .to_return(status: 200, body: [-9].to_json)

    check.for_entry(mega_entry('abcdEFGH#key'))

    expect(request).to have_been_made.once
  end

  describe 'MEGA not answering, which is never the same as broken' do
    let(:entry) { mega_entry('abcdEFGH#key') }

    it 'is unknown on a rate limit or a try-again' do
      answer(-3)

      expect(check.for_entry(entry)).to be_unknown
    end

    it 'is unknown when the whole request is refused with one bare code' do
      stub_request(:post, api).to_return(status: 200, body: '-4')

      expect(check.for_entry(entry)).to be_unknown
    end

    it 'is unknown on a server error' do
      stub_request(:post, api).to_return(status: 500, body: '')

      expect(check.for_entry(entry)).to be_unknown
    end

    it 'is unknown when MEGA cannot be reached' do
      stub_request(:post, api).to_raise(Errno::ECONNREFUSED)

      expect(check.for_entry(entry)).to be_unknown
    end

    it 'is unknown on an answer it cannot read' do
      stub_request(:post, api).to_return(status: 200, body: 'not json')

      expect(check.for_entry(entry)).to be_unknown
    end
  end

  # Fifty to a request, answers matched back to the entries they belong to in order.
  it 'asks about many links in batches and keeps each answer with its own entry' do
    entries = Array.new(60) { |i| mega_entry(format('h%07d#key', i), name: "Film #{i}") }
    stub_request(:post, api).to_return do |request|
      handles = JSON.parse(request.body).map { |command| command['p'] }
      { status: 200, body: handles.map { |handle| handle.end_with?('7') ? -9 : -3 }.to_json }
    end

    results = check.for_entries(entries)

    expect(a_request(:post, api)).to have_been_made.twice
    expect(results.count { |_, result| result.missing? }).to eq(6)
    expect(results[entries[7].id]).to be_missing
    expect(results[entries[8].id]).to be_unknown
  end

  describe 'as the check an entry runs on itself' do
    it 'is used for a MEGA entry instead of the page-title check' do
      key, attributes = key_and_attributes
      answer({ s: 1234, at: attributes })
      entry = mega_entry("abcdEFGH##{key}")
      entry.update_columns(stream: false)

      expect(UrlCheckerService).not_to receive(:new)
      entry.check_source

      expect(entry.reload.stream).to be(true)
    end

    it 'leaves the mark as it was when MEGA does not answer' do
      stub_request(:post, api).to_return(status: 503, body: '')
      entry = mega_entry('abcdEFGH#key')
      entry.update_columns(stream: true)

      entry.check_source

      expect(entry.reload.stream).to be(true)
    end

    it 'applies to an entry whose channel plays from MEGA' do
      list.update!(provider: mega)
      entry = create(:entry, list: list, name: 'Inherits', provider: nil, source_key: 'abcdEFGH#key', imdb: nil)

      expect(described_class.applies_to?(entry)).to be(true)
    end
  end
end
