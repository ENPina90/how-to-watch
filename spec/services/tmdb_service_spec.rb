require 'rails_helper'

RSpec.describe TmdbService do
  subject(:tmdb) { described_class.new }

  # The test env uses a null store, so caching is exercised explicitly here.
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end

  let(:episode_url) { %r{api\.themoviedb\.org/3/tv/1396/season/1/episode/1} }

  describe 'caching' do
    it 'makes one request for repeated identical lookups' do
      stub_request(:get, episode_url).to_return(status: 200, body: { 'name' => 'Pilot' }.to_json)

      3.times { tmdb.fetch_episode('1396', 1, 1) }

      expect(a_request(:get, episode_url)).to have_been_made.once
    end

    it 'does not conflate different episodes' do
      stub_request(:get, episode_url).to_return(status: 200, body: { 'name' => 'Pilot' }.to_json)
      other = %r{api\.themoviedb\.org/3/tv/1396/season/1/episode/2}
      stub_request(:get, other).to_return(status: 200, body: { 'name' => 'Cat in the Bag' }.to_json)

      expect(tmdb.fetch_episode('1396', 1, 1)['name']).to eq('Pilot')
      expect(tmdb.fetch_episode('1396', 1, 2)['name']).to eq('Cat in the Bag')
    end

    it 'does not cache failures' do
      stub_request(:get, episode_url).to_return({ status: 500, body: 'nope' },
                                                { status: 200, body: { 'name' => 'Pilot' }.to_json })

      expect { tmdb.fetch_episode('1396', 1, 1) }.to raise_error(described_class::RequestError)
      expect(tmdb.fetch_episode('1396', 1, 1)['name']).to eq('Pilot')
    end

    it 'keeps the api key out of the cache key' do
      stub_request(:get, episode_url).to_return(status: 200, body: '{}')

      tmdb.fetch_episode('1396', 1, 1)

      keys = Rails.cache.instance_variable_get(:@data).keys
      expect(keys.join).not_to include(described_class.api_key)
    end
  end

  describe 'error handling' do
    it 'raises RequestError for a non-success response' do
      stub_request(:get, %r{api\.themoviedb\.org/3/tv/999}).to_return(status: 404, body: 'not found')

      expect { tmdb.fetch_show('999') }.to raise_error(described_class::RequestError, /404/)
    end

    it 'raises RequestError for unparseable json' do
      stub_request(:get, %r{api\.themoviedb\.org/3/tv/999}).to_return(status: 200, body: '<html>')

      expect { tmdb.fetch_show('999') }.to raise_error(described_class::RequestError, /unparseable/)
    end

    it 'keeps the nil-on-error contract for the poster helper' do
      stub_request(:get, %r{api\.themoviedb\.org/3/movie/1}).to_return(status: 500, body: '')

      expect(tmdb.fetch_poster_url('1')).to be_nil
    end
  end

  describe '.image_url' do
    it 'builds a full url from a path' do
      expect(described_class.image_url('/x.jpg')).to eq('https://image.tmdb.org/t/p/w500/x.jpg')
    end

    it 'returns nil when there is no path' do
      expect(described_class.image_url(nil)).to be_nil
    end
  end
end
