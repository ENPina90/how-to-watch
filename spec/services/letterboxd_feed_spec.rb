# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LetterboxdFeed do
  let(:feed_url) { 'https://letterboxd.com/testmember/rss/' }
  let(:body) { Rails.root.join('spec/fixtures/letterboxd/diary.xml').read }

  def stub_feed(status: 200, body: self.body)
    stub_request(:get, feed_url).to_return(status: status, body: body)
  end

  describe '.valid_username?' do
    it 'accepts the shapes Letterboxd issues' do
      expect(described_class).to be_valid_username('testmember')
      expect(described_class).to be_valid_username('a_b_1')
    end

    # The check endpoint is reachable while signed out, so the name must never be able to
    # walk out of the /<name>/rss/ path.
    it 'rejects anything that could escape the feed path' do
      ['../../admin', 'has space', 'name/rss', '', 'a' * 33, nil].each do |bad|
        expect(described_class).not_to be_valid_username(bad), "expected #{bad.inspect} to be rejected"
      end
    end
  end

  describe '#watches' do
    before { stub_feed }

    subject(:watches) { described_class.new('testmember').watches }

    it 'skips list items, which share the feed with diary entries' do
      expect(watches.map(&:guid)).to all(start_with('letterboxd-watch-'))
    end

    it 'skips diary entries with no TMDB id, which nothing could be matched against' do
      expect(watches.map(&:title)).not_to include('Some Obscure Short')
    end

    it 'reads the fields the sync needs' do
      watch = watches.first

      expect(watch).to have_attributes(
        tmdb_id: '1171145',
        title: 'Crime 101',
        year: 2026,
        rating: 3.5,
        watched_on: Date.new(2026, 8, 28),
        poster_url: 'https://a.ltrbxd.com/poster/crime-101.jpg',
        # Only /film/<slug>/ accepts the /review/ suffix, and the feed gives it away
        # free -- resolving it later costs a request per film.
        slug: 'crime-101'
      )
      expect(watch).not_to be_rewatch
    end

    it 'keeps the review and drops the poster and the closing sentence around it' do
      expect(watches.first.review).to eq("Lean and mean.\n\nSecond paragraph.")
    end

    # An unrated watch is ordinary. It must come back as nil rather than 0.0, which would
    # otherwise be stored as a real zero-star score.
    it 'leaves an unrated watch with no rating and no review' do
      odyssey = watches.find { |w| w.title == 'The Odyssey' }

      expect(odyssey.rating).to be_nil
      expect(odyssey.review).to be_nil
      expect(odyssey).to be_rewatch
    end
  end

  describe '#readable?' do
    it 'is true for a member with a public diary' do
      stub_feed
      expect(described_class.new('testmember')).to be_readable
    end

    # A private profile publishes no feed, so from outside it is indistinguishable from a
    # name that does not exist. Both answer false rather than raising.
    it 'is false when the feed is missing or unreadable' do
      stub_feed(status: 404, body: '')
      expect(described_class.new('testmember')).not_to be_readable
    end

    it 'is false when the name is real but has never logged a film' do
      stub_feed(body: '<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>')
      expect(described_class.new('testmember')).not_to be_readable
    end

    it 'is false without making a request when the name is malformed' do
      expect(described_class.new('../admin')).not_to be_readable
      expect(a_request(:get, %r{letterboxd\.com})).not_to have_been_made
    end
  end

  describe 'failures' do
    it 'raises rather than returning a half-parsed diary' do
      stub_feed(status: 500, body: '')
      expect { described_class.new('testmember').watches }
        .to raise_error(described_class::RequestError, /returned 500/)
    end

    it 'raises when the feed times out' do
      stub_request(:get, feed_url).to_timeout
      expect { described_class.new('testmember').watches }
        .to raise_error(described_class::RequestError, /failed/)
    end
  end
end
