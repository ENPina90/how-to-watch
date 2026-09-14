# frozen_string_literal: true

require 'rails_helper'

# Reading a playlist through the Data API. What matters is that it reads the whole of one --
# every page, every batch of details -- and that what it cannot read comes back as a sentence
# for the person who pasted the link rather than as an exception or a short list.
RSpec.describe YoutubePlaylist do
  let(:playlist_id) { 'PLYi6bn_TN8EK-Y3W5ytMPTehcaUUIYA1R' }

  around do |example|
    original = ENV.values_at('YOUTUBE_API_KEY', 'GOOGLE_SEARCH_API_KEY')
    ENV['YOUTUBE_API_KEY'] = 'test-key'
    ENV['GOOGLE_SEARCH_API_KEY'] = nil
    example.run
    ENV['YOUTUBE_API_KEY'], ENV['GOOGLE_SEARCH_API_KEY'] = original
  end

  # Takes the body either as a hash or as bare keywords, which is how `json(items: [...])`
  # arrives.
  def json(body = nil, status: 200, **fields)
    { status: status, body: (body || fields).to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_playlist(title: 'Last Stream on the Left full episodes', count: 2)
    stub_request(:get, %r{youtube/v3/playlists\?})
      .to_return(json(items: [{ snippet: { title: title }, contentDetails: { itemCount: count } }]))
  end

  def stub_items(pages)
    stubs = pages.each_with_index.map do |ids, index|
      body = { items: ids.map { |id| { contentDetails: { videoId: id } } } }
      body[:nextPageToken] = "page#{index + 1}" if index < pages.size - 1
      json(body)
    end

    stub_request(:get, %r{youtube/v3/playlistItems\?}).to_return(*stubs)
  end

  def video(id, title: "Video #{id}", duration: 'PT1H3M50S', embeddable: true, rating: {})
    {
      id: id,
      snippet: {
        title: title,
        description: "About #{id}",
        publishedAt: '2021-07-23T00:00:01Z',
        thumbnails: { high: { url: "https://i.ytimg.com/vi/#{id}/hqdefault.jpg" },
                      maxres: { url: "https://i.ytimg.com/vi/#{id}/maxresdefault.jpg" } }
      },
      contentDetails: { duration: duration, contentRating: rating },
      status: { embeddable: embeddable }
    }
  end

  def stub_videos(*videos)
    stub_request(:get, %r{youtube/v3/videos\?}).to_return(json(items: videos))
  end

  describe '.id_from' do
    it 'reads the id out of a playlist link' do
      expect(described_class.id_from("https://www.youtube.com/playlist?list=#{playlist_id}")).to eq(playlist_id)
    end

    it 'reads it out of a watch link playing from the playlist' do
      expect(described_class.id_from("https://www.youtube.com/watch?v=0_paCykOQNI&list=#{playlist_id}&index=2"))
        .to eq(playlist_id)
    end

    it 'takes a bare id' do
      expect(described_class.id_from(" #{playlist_id} ")).to eq(playlist_id)
    end

    it 'refuses anything that is not a playlist' do
      expect(described_class.id_from('https://www.youtube.com/watch?v=0_paCykOQNI')).to be_nil
      expect(described_class.id_from('')).to be_nil
    end
  end

  describe '.fetch' do
    it 'reads every video with what an entry needs from it' do
      stub_playlist
      stub_items([%w[aaa bbb]])
      stub_videos(video('aaa', title: 'S1 EP1'), video('bbb', title: 'S1 EP2', duration: 'PT59M3S'))

      playlist = described_class.fetch("https://www.youtube.com/playlist?list=#{playlist_id}")

      expect(playlist.title).to eq('Last Stream on the Left full episodes')
      expect(playlist.videos.map(&:title)).to eq(['S1 EP1', 'S1 EP2'])

      first = playlist.videos.first
      expect(first.youtube_id).to eq('aaa')
      expect(first.duration_seconds).to eq(3830)
      expect(first.description).to eq('About aaa')
      expect(first.published_at.year).to eq(2021)
      # The only 16:9 one of the large sizes.
      expect(first.thumbnail_url).to eq('https://i.ytimg.com/vi/aaa/maxresdefault.jpg')
      expect(first).to be_playable
    end

    it 'follows the pages to the end of the playlist' do
      stub_playlist(count: 3)
      stub_items([%w[aaa bbb], %w[ccc]])
      stub_videos(video('aaa'), video('bbb'), video('ccc'))

      expect(described_class.fetch(playlist_id).videos.map(&:youtube_id)).to eq(%w[aaa bbb ccc])
      expect(a_request(:get, %r{playlistItems}).with(query: hash_including('pageToken' => 'page1'))).to have_been_made
    end

    # The API does not promise its own order, and the playlist's is the one that means
    # something.
    it 'keeps playlist order however the details come back' do
      stub_playlist
      stub_items([%w[aaa bbb]])
      stub_videos(video('bbb'), video('aaa'))

      expect(described_class.fetch(playlist_id).videos.map(&:youtube_id)).to eq(%w[aaa bbb])
    end

    it 'counts the deleted and private videos it could not read' do
      stub_playlist(count: 2)
      stub_items([%w[aaa gone]])
      stub_videos(video('aaa'))

      playlist = described_class.fetch(playlist_id)

      expect(playlist.videos.map(&:youtube_id)).to eq(%w[aaa])
      expect(playlist.unavailable).to eq(1)
    end

    it 'reads a video whose owner switched embedding off as unplayable' do
      stub_playlist
      stub_items([%w[aaa]])
      stub_videos(video('aaa', embeddable: false))

      expect(described_class.fetch(playlist_id).videos.sole).not_to be_playable
    end

    # YouTube's embed refuses these often but not always, and leaving them out would put holes
    # in a series.
    it 'marks an age-restricted video without calling it unplayable' do
      stub_playlist
      stub_items([%w[aaa]])
      stub_videos(video('aaa', rating: { ytRating: 'ytAgeRestricted' }))

      video = described_class.fetch(playlist_id).videos.sole
      expect(video.age_restricted).to be(true)
      expect(video).to be_playable
    end

    it 'has no runtime for a live stream rather than a runtime of nothing' do
      stub_playlist
      stub_items([%w[aaa]])
      stub_videos(video('aaa', duration: 'P0D'))

      expect(described_class.fetch(playlist_id).videos.sole.duration_seconds).to be_nil
    end
  end

  describe 'what it cannot read' do
    def failure_for(url)
      described_class.fetch(url)
    rescue described_class::RequestError => e
      e.message
    end

    it 'says so when there is no key, without asking YouTube' do
      ENV['YOUTUBE_API_KEY'] = nil

      expect(failure_for(playlist_id)).to include('No YouTube API key')
      expect(a_request(:get, /googleapis/)).not_to have_been_made
    end

    # Both are keys onto the same Google Cloud project; the image search one is the one set.
    it 'falls back to the Google search key' do
      ENV['YOUTUBE_API_KEY'] = nil
      ENV['GOOGLE_SEARCH_API_KEY'] = 'search-key'
      stub_playlist
      stub_items([[]])
      stub_videos

      described_class.fetch(playlist_id)

      expect(a_request(:get, /playlists/).with(query: hash_including('key' => 'search-key'))).to have_been_made
    end

    it 'refuses a link that is not a playlist' do
      expect(failure_for('https://www.youtube.com/watch?v=0_paCykOQNI')).to include('not a link to a YouTube playlist')
    end

    # A private playlist answers exactly like a missing one.
    it 'says so when there is no public playlist there' do
      stub_request(:get, %r{youtube/v3/playlists\?}).to_return(json(items: []))

      expect(failure_for(playlist_id)).to include('no public playlist')
    end

    it 'refuses a playlist too long to import in one go, before reading any of it' do
      stub_playlist(count: described_class::MAX_VIDEOS + 1)

      expect(failure_for(playlist_id)).to include("#{described_class::MAX_VIDEOS} is the most")
      expect(a_request(:get, /playlistItems/)).not_to have_been_made
    end

    it 'explains a spent quota' do
      stub_request(:get, %r{youtube/v3/playlists\?})
        .to_return(json({ error: { errors: [{ reason: 'quotaExceeded' }] } }, status: 403))

      expect(failure_for(playlist_id)).to include('quota')
    end

    it 'never repeats the key in what it says' do
      stub_request(:get, %r{youtube/v3/playlists\?})
        .to_return(json({ error: { errors: [{ reason: 'keyInvalid' }] } }, status: 400))

      expect(failure_for(playlist_id)).not_to include('test-key')
    end

    it 'says so when YouTube cannot be reached' do
      stub_request(:get, %r{youtube/v3/playlists\?}).to_timeout

      expect(failure_for(playlist_id)).to eq('Could not reach YouTube')
    end
  end
end
