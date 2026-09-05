# frozen_string_literal: true

require 'rails_helper'

# The one poster source that needs credentials the app does not already have, and the one
# that returns whatever is on the open web. Both of those shape what it has to do: stay
# silent when it is not configured, and throw away what is obviously not a poster.
RSpec.describe GoogleImageSearch do
  def configured
    ENV['GOOGLE_SEARCH_API_KEY'] = 'test-key'
    ENV['GOOGLE_SEARCH_ENGINE_ID'] = 'test-cx'
  end

  around do |example|
    original = ENV.values_at('GOOGLE_SEARCH_API_KEY', 'GOOGLE_SEARCH_ENGINE_ID')
    example.run
    ENV['GOOGLE_SEARCH_API_KEY'], ENV['GOOGLE_SEARCH_ENGINE_ID'] = original
  end

  def answering(items)
    stub_request(:get, /googleapis\.com\/customsearch/)
      .to_return(status: 200, body: { items: items }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def image(link, width:, height:)
    { 'link' => link, 'image' => { 'width' => width, 'height' => height } }
  end

  it 'says nothing at all when the keys are not set' do
    ENV['GOOGLE_SEARCH_API_KEY'] = nil
    ENV['GOOGLE_SEARCH_ENGINE_ID'] = nil

    expect(described_class.new.call('The Avengers 2012 poster')).to eq([])
    expect(a_request(:get, /googleapis/)).not_to have_been_made
  end

  it 'returns the images it found, with the host they came from' do
    configured
    answering([image('https://fanart.example/a.jpg', width: 600, height: 900)])

    expect(described_class.new.call('The Avengers 2012 poster')).to eq(
      [{ url: 'https://fanart.example/a.jpg', host: 'fanart.example', width: 600, height: 900 }]
    )
  end

  it 'searches for images, safely, rather than for pages' do
    configured
    answering([])

    described_class.new.call('The Avengers 2012 poster')

    expect(a_request(:get, /googleapis/).with(query: hash_including('searchType' => 'image', 'safe' => 'active')))
      .to have_been_made
  end

  # Image search returns a great many banners, logos and screengrabs. Offering those as
  # posters is most of what makes a picker feel random.
  it 'drops landscape images when it was asked for posters' do
    configured
    answering([image('https://fanart.example/banner.jpg', width: 1200, height: 400),
               image('https://fanart.example/poster.jpg', width: 600, height: 900)])

    urls = described_class.new.call('The Avengers poster').map { |r| r[:url] }

    expect(urls).to eq(['https://fanart.example/poster.jpg'])
  end

  it 'keeps landscape images when it was not' do
    configured
    answering([image('https://fanart.example/still.jpg', width: 1200, height: 675)])

    results = described_class.new.call('Seinfeld s6e10', portrait_only: false)

    expect(results.map { |r| r[:url] }).to eq(['https://fanart.example/still.jpg'])
  end

  it 'drops results the picker could not display anyway' do
    configured
    answering([image('http://insecure.example/a.jpg', width: 600, height: 900)])

    expect(described_class.new.call('The Avengers poster')).to eq([])
  end

  # It is the least trustworthy source in the picker; a failure here must cost nothing but
  # its own results.
  it 'returns nothing rather than raising when the request fails' do
    configured
    stub_request(:get, /googleapis/).to_return(status: 429, body: 'over quota')

    expect(described_class.new.call('The Avengers poster')).to eq([])
  end

  it 'returns nothing rather than raising when the network is down' do
    configured
    stub_request(:get, /googleapis/).to_raise(Errno::ECONNREFUSED)

    expect(described_class.new.call('The Avengers poster')).to eq([])
  end
end
