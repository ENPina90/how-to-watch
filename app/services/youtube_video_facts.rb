# frozen_string_literal: true

# What YouTube will say about one video, read off its watch page.
#
# Three things the app needs and no API hands over without a key: how long the video runs,
# whether it can be embedded at all, and what it is called. `commercials:durations` and
# `commercials:check` each used to scrape their own half of this; the admin page needs both
# at once, so they live here and the tasks call in.
#
# `lengthSeconds` and `playableInEmbed` are not documented and could move. That is why a
# fact this cannot read comes back nil rather than false: "we could not tell" and "no" are
# different answers, and treating the first as the second is how a sweep reports a clean
# result it cannot actually vouch for.
class YoutubeVideoFacts
  AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' \
          '(KHTML, like Gecko) Chrome/120.0 Safari/537.36'
  TIMEOUT = 15

  Facts = Struct.new(:title, :duration_seconds, :embeddable, :exists, :error, keyword_init: true) do
    def ok? = error.nil?
  end

  def self.for(...) = new(...).call

  def initialize(youtube_id)
    @youtube_id = youtube_id.to_s
  end

  def call
    return Facts.new(error: 'No YouTube id') if @youtube_id.blank?

    oembed = fetch_oembed
    # oEmbed answers whether the video is there and public. It says nothing about
    # embedding -- it returns 200 for a video no embed will ever play -- so it is the first
    # of two questions rather than the whole of one.
    return Facts.new(exists: false, error: "Gone or private (HTTP #{oembed.code})") unless oembed.code == 200

    page = fetch_watch_page

    Facts.new(
      title: oembed.parsed_response['title'].to_s.presence,
      duration_seconds: page[/"lengthSeconds":"(\d+)"/, 1]&.to_i,
      embeddable: embeddable_from(page),
      exists: true
    )
  rescue StandardError => e
    Rails.logger.warn("YoutubeVideoFacts could not read #{@youtube_id}: #{e.class}: #{e.message}")
    Facts.new(error: 'Could not reach YouTube')
  end

  private

  def watch_url = "https://www.youtube.com/watch?v=#{@youtube_id}"

  def fetch_oembed
    HTTParty.get("https://www.youtube.com/oembed?format=json&url=#{CGI.escape(watch_url)}",
                 timeout: TIMEOUT)
  end

  def fetch_watch_page
    HTTParty.get(watch_url, headers: { 'User-Agent' => AGENT }, timeout: TIMEOUT).body.to_s
  end

  # nil where the flag is not in the page at all, which is "could not tell" rather than "no".
  def embeddable_from(page)
    flag = page[/"playableInEmbed":(true|false)/, 1]
    return nil if flag.nil?

    flag == 'true'
  end
end
