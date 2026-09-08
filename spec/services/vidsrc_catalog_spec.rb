# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VidsrcCatalog do
  let!(:vidsrc) do
    Source.create!(name: 'Framerelay', slug: 'framerelay', kind: 'imdb', active: true, position: 1,
                   templates: { 'movie' => 'https://framerelay.dev/embed/movie?imdb=%{imdb}' })
  end

  def dump(file, ids)
    stub_request(:get, "https://framerelay.dev/ids/#{file}").to_return(status: 200, body: ids.join("\n"))
  end

  def full(prefix) = Array.new(1_500) { |i| "#{prefix}#{i}" }

  before do
    dump('movie_imdb.txt', full('tt') + %w[tt0172495])
    dump('tv_imdb.txt', full('tv') + %w[tt0098904])
    dump('eps_imdb.txt', full('ep') + %w[tt0041038_1x1])
  end

  it 'answers for a film, a show and an episode' do
    catalog = described_class.new

    expect(catalog.movie?('tt0172495')).to be(true)
    expect(catalog.movie?('tt0177242')).to be(false)
    expect(catalog.show?('tt0098904')).to be(true)
    expect(catalog.episode?('tt0041038', 1, 1)).to be(true)
    expect(catalog.episode?('tt0041038', 9, 9)).to be(false)
  end

  # The dumps key episodes without padding, and season/episode reach this as integers or
  # as strings depending on where they came from.
  it 'keys an episode the way the dump does' do
    expect(described_class.new.episode?('tt0041038', '1', '1')).to be(true)
  end

  # Reading the host off the templates is what lets a domain rotation carry this with it;
  # VIDSRC.md §1a is about the things that get left behind.
  it 'asks whichever vidsrc domain the app is currently pointing at' do
    described_class.new.movie?('tt0172495')

    expect(a_request(:get, 'https://framerelay.dev/ids/movie_imdb.txt')).to have_been_made
  end

  describe 'refusing to answer' do
    # An empty or truncated dump reads as "VidSrc can play nothing", which downstream would
    # condemn every entry in the app.
    it 'rejects a dump too small to be real' do
      dump('movie_imdb.txt', %w[tt0000001 tt0000002])

      expect { described_class.new.movie?('tt0172495') }.to raise_error(described_class::Unavailable, /2 ids/)
    end

    it 'raises rather than answering when the request fails' do
      stub_request(:get, %r{framerelay\.dev/ids/}).to_return(status: 503, body: '')

      expect { described_class.new.warm! }.to raise_error(described_class::Unavailable, /503/)
    end

    it 'raises when there is no active vidsrc provider to ask' do
      vidsrc.update!(active: false)

      expect { described_class.new.warm! }.to raise_error(described_class::Unavailable, /No active vidsrc/)
    end
  end
end
