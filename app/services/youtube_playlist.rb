# frozen_string_literal: true

# Reads a public YouTube playlist through the Data API: its title, and for every video in it
# the id, title, description, runtime, thumbnail and whether an embed will play it.
#
# The API rather than the playlist page. The page carries the first hundred videos in
# undocumented JSON that YouTube renames from time to time -- YoutubeVideoFacts lives with
# that for one video at a time, but an import that quietly stops at a hundred is worse than
# one that fails. The API is documented, pages properly, and costs one unit a call against a
# free 10,000 a day: a playlist of 109 videos is seven calls.
#
# Reads only. YoutubePlaylistImporter decides what becomes of the videos, the way
# LetterboxdFeed reads a diary and LetterboxdList files it.
class YoutubePlaylist
  API = 'https://www.googleapis.com/youtube/v3'
  TIMEOUT = 15

  # The most the API hands back in one call, for both the playlist pages and the batches of
  # video details.
  PAGE_SIZE = 50

  # An import runs inside the request so its result can be told to whoever pasted the link,
  # and every video becomes a row plus two queued jobs. A playlist over this is refused up
  # front rather than cut short, so nobody is left with the first half of a series.
  MAX_VIDEOS = 500

  # Playlist ids are PL..., UU..., OLAK5uy_... and a few other shapes, all URL-safe base64.
  # Checked before the id reaches a query string, and loose on length because the prefixes
  # differ in it.
  PLAYLIST_ID = /\A[\w-]{12,64}\z/

  class RequestError < StandardError; end

  Playlist = Struct.new(:id, :title, :videos, :unavailable, keyword_init: true)

  Video = Struct.new(
    :youtube_id, :title, :description, :duration_seconds, :thumbnail_url, :published_at,
    :embeddable, :age_restricted,
    keyword_init: true
  ) do
    # An owner can switch embedding off, and then the frame on the watch page is a refusal
    # for everyone. nil is "the API did not say", which is not the same as no.
    #
    # Age-restricted videos are left playable on purpose. YouTube's embed often sends the
    # viewer to youtube.com for them, but not always, and a playlist of a show had ten of
    # them in 109 episodes -- leaving them out would put holes in a series for a refusal
    # that may never happen. The importer says which they are instead.
    def playable? = embeddable != false
  end

  # The one Google Cloud key this app has. YOUTUBE_API_KEY is read first so the two can be
  # split later without a code change -- a key restricted to image search would be refused
  # here, and one restricted to YouTube would be refused there.
  def self.api_key = ENV['YOUTUBE_API_KEY'].presence || ENV['GOOGLE_SEARCH_API_KEY'].presence

  def self.configured? = api_key.present?

  # A pasted link -> playlist id, or nil. Takes the playlist page, a watch link that is
  # playing from a playlist, or a bare id.
  def self.id_from(url)
    text = url.to_s.strip
    id = text[/[?&]list=([\w-]+)/, 1] || text

    id.match?(PLAYLIST_ID) ? id : nil
  end

  def self.fetch(url) = new(id_from(url)).call

  def initialize(id)
    @id = id
  end

  # Raises RequestError, with a message fit to show whoever pasted the link.
  def call
    raise RequestError, 'No YouTube API key is set' unless self.class.configured?
    raise RequestError, 'That is not a link to a YouTube playlist' if @id.blank?

    playlist = get('playlists', part: 'snippet,contentDetails', id: @id)['items'].to_a.first
    # A private playlist answers the same as one that does not exist: no items.
    raise RequestError, 'YouTube has no public playlist at that link' if playlist.nil?

    count = playlist.dig('contentDetails', 'itemCount').to_i
    if count > MAX_VIDEOS
      raise RequestError, "That playlist has #{count} videos; #{MAX_VIDEOS} is the most one import can take"
    end

    ids = video_ids
    videos = details_for(ids)

    Playlist.new(id: @id, title: playlist.dig('snippet', 'title').to_s.strip,
                 videos: videos, unavailable: ids.size - videos.size)
  end

  private

  # In playlist order. A video in the playlist twice is imported once, where it first
  # appears.
  def video_ids
    ids = []
    token = nil

    loop do
      page = get('playlistItems', part: 'contentDetails', playlistId: @id,
                                  maxResults: PAGE_SIZE, pageToken: token)
      ids.concat(page['items'].to_a.filter_map { |item| item.dig('contentDetails', 'videoId') })
      token = page['nextPageToken']
      break if token.blank?
    end

    ids.uniq
  end

  # The playlist lists deleted and private videos too, and videos.list simply leaves them
  # out -- so whatever does not come back is what the playlist holds and nobody can watch.
  # The API does not promise to answer in the order it was asked, hence the index.
  def details_for(ids)
    found = ids.each_slice(PAGE_SIZE).flat_map do |batch|
      get('videos', part: 'snippet,contentDetails,status', id: batch.join(','), maxResults: PAGE_SIZE)['items'].to_a
    end.index_by { |item| item['id'] }

    ids.filter_map { |id| found[id] && video_from(found[id]) }
  end

  def video_from(item)
    snippet = item['snippet'] || {}

    Video.new(
      youtube_id: item['id'],
      title: snippet['title'].to_s.strip,
      description: snippet['description'].to_s.strip.presence,
      duration_seconds: seconds_in(item.dig('contentDetails', 'duration')),
      thumbnail_url: thumbnail_in(snippet['thumbnails']),
      published_at: time_in(snippet['publishedAt']),
      embeddable: item.dig('status', 'embeddable'),
      age_restricted: item.dig('contentDetails', 'contentRating', 'ytRating') == 'ytAgeRestricted'
    )
  end

  # ISO 8601, "PT1H3M50S". Nil rather than zero for a live stream or a premiere, whose
  # duration is P0D: no runtime is a different answer from a runtime of nothing.
  def seconds_in(duration)
    seconds = ActiveSupport::Duration.parse(duration.to_s).to_i
    seconds.positive? ? seconds : nil
  rescue ActiveSupport::Duration::ISO8601Parser::ParsingError
    nil
  end

  # maxres is the only 16:9 one of the large sizes; standard and high are 4:3 with the
  # picture letterboxed inside them. Not every video has maxres, so the rest are fallbacks.
  THUMBNAIL_SIZES = %w[maxres standard high medium default].freeze

  def thumbnail_in(thumbnails)
    return nil if thumbnails.blank?

    THUMBNAIL_SIZES.lazy.filter_map { |size| thumbnails.dig(size, 'url') }.first
  end

  def time_in(value)
    value.present? ? Time.iso8601(value) : nil
  rescue ArgumentError
    nil
  end

  def get(resource, **params)
    response = HTTParty.get("#{API}/#{resource}", query: params.compact.merge(key: self.class.api_key),
                                                  timeout: TIMEOUT)
    raise RequestError, refusal(response) unless response.code == 200

    response.parsed_response
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
    Rails.logger.warn("YoutubePlaylist could not reach YouTube for #{@id}: #{e.class}: #{e.message}")
    raise RequestError, 'Could not reach YouTube'
  end

  # The key itself never goes in the message: it ends up in a flash and in logs.
  def refusal(response)
    body = response.parsed_response
    reason = body.is_a?(Hash) ? body.dig('error', 'errors', 0, 'reason') : nil
    Rails.logger.warn("YoutubePlaylist refused for #{@id}: HTTP #{response.code} #{reason}")

    case reason
    when 'playlistNotFound' then 'YouTube has no public playlist at that link'
    when 'quotaExceeded' then "Today's YouTube API quota is used up; try again tomorrow"
    when 'keyInvalid', 'accessNotConfigured', 'forbidden', 'ipRefererBlocked'
      'YouTube refused the API key — check YouTube Data API v3 is enabled for it'
    else "YouTube refused the request (HTTP #{response.code})"
    end
  end
end
