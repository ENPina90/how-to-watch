# frozen_string_literal: true

require 'rails_helper'

# Two questions about one video, because they are two different flags: oEmbed answers
# whether it is there and public, and `playableInEmbed` answers whether it can be embedded.
# Only asking the first is how a sweep reports a clean result it cannot vouch for.
RSpec.describe YoutubeVideoFacts do
  let(:watch_url) { 'https://www.youtube.com/watch?v=abc123' }
  let(:oembed_url) { %r{youtube\.com/oembed} }

  def stub_oembed(status: 200, title: 'Commercials 1987')
    stub_request(:get, oembed_url)
      .to_return(status: status, body: { title: title }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_watch(body)
    stub_request(:get, watch_url).to_return(status: 200, body: body)
  end

  it 'reads the title, the runtime and whether it can be embedded' do
    stub_oembed
    stub_watch('{"lengthSeconds":"2461","playableInEmbed":true}')

    facts = described_class.for('abc123')

    expect(facts).to be_ok
    expect(facts.title).to eq('Commercials 1987')
    expect(facts.duration_seconds).to eq(2461)
    expect(facts.embeddable).to be(true)
  end

  it 'reports a video whose owner has switched embedding off' do
    stub_oembed
    stub_watch('{"lengthSeconds":"2461","playableInEmbed":false}')

    expect(described_class.for('abc123').embeddable).to be(false)
  end

  # oEmbed returns 200 for a video no embed will ever play, so it is the first of two
  # questions rather than the whole of one.
  it 'says a video is gone when oEmbed will not answer for it' do
    stub_oembed(status: 404)

    facts = described_class.for('abc123')

    expect(facts.exists).to be(false)
    expect(facts.error).to include('Gone or private')
  end

  # "We could not tell" and "no" are different answers. Neither flag is documented, and
  # treating a missing one as a refusal would strike off reels that are perfectly fine.
  it 'answers nil rather than false when the page carries no flag' do
    stub_oembed
    stub_watch('<html>nothing useful here</html>')

    facts = described_class.for('abc123')

    expect(facts.embeddable).to be_nil
    expect(facts.duration_seconds).to be_nil
    expect(facts).to be_ok
  end

  it 'reports a network failure rather than raising' do
    stub_request(:get, oembed_url).to_timeout

    expect(described_class.for('abc123').error).to be_present
  end

  it 'has nothing to ask about an empty id' do
    expect(described_class.for('').error).to be_present
    expect(WebMock).not_to have_requested(:get, oembed_url)
  end
end
