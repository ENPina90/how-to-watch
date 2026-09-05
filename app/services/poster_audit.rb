# frozen_string_literal: true

# Asks every entry's poster URL whether the image is really there.
#
# Posters go missing in Cloudinary rather than in the database: the attachment row, the key
# and the pic column all still look filled in, and the only place the loss shows is a blank
# frame on a channel row. So this asks for the URL the page asks for -- ImageHelper decides
# that, and deciding it twice is how the audit would drift away from what is rendered --
# and requests it.
#
# Read-only by design. ImageRepairService is the one that changes things, and it only ever
# looks at `pic`; most entries no longer render from that column.
class PosterAudit
  include ImageHelper

  Row = Struct.new(:entry, :url, :source, :reason, keyword_init: true)
  Result = Struct.new(:checked, :broken, keyword_init: true)

  REDIRECT_LIMIT = 3
  DEFAULT_CONCURRENCY = 12

  def self.call(...) = new(...).call

  # `progress` is called with (done, total) as the checks come back, for the rake task's
  # counter. Left nil by the job, which has nobody watching.
  def initialize(scope: Entry.all, concurrency: DEFAULT_CONCURRENCY, progress: nil)
    @scope = scope
    @concurrency = concurrency
    @progress = progress
  end

  def call
    targets = collect_targets

    Result.new(checked: targets.size, broken: examine_all(targets))
  end

  private

  # Gathered up front, in one pass, so the checks below can run on threads without every
  # one of them reaching for a database connection: the pool is five wide and the checks
  # are a dozen.
  def collect_targets
    @scope.includes(:list, poster_attachment: :blob).map do |entry|
      { entry: entry, url: entry_poster_url(entry).presence }
    end
  end

  def examine_all(targets)
    queue = Queue.new
    targets.each_with_index { |target, index| queue << [index, target] }

    results = Array.new(targets.size)
    mutex = Mutex.new
    done = 0

    workers = Array.new([@concurrency, targets.size].min) do
      Thread.new do
        while (job = begin
          queue.pop(true)
        rescue ThreadError
          nil
        end)
          index, target = job
          results[index] = examine(target)
          mutex.synchronize { @progress&.call(done += 1, targets.size) }
        end
      end
    end
    workers.each(&:join)

    results.compact
  end

  def examine(target)
    entry = target[:entry]
    source = entry.poster.attached? ? 'poster' : 'pic'

    # Nothing to point the tag at: these render as an empty frame with the alt text in it,
    # which is what a missing poster looks like on the channel row.
    return row(target, source, 'no image on the entry') if target[:url].blank?

    reason = failure_for(target[:url])
    reason && row(target, source, reason)
  end

  def row(target, source, reason)
    Row.new(entry: target[:entry], url: target[:url], source: source, reason: reason)
  end

  # nil when the URL serves an image, a short description of the problem otherwise.
  def failure_for(url, redirects: REDIRECT_LIMIT)
    # A handful of entries carry the image inline rather than linking to it. There is
    # nothing to request, and the browser renders it, so it is not broken.
    return nil if url.start_with?('data:image/')

    uri = URI.parse(url)
    return 'not an http(s) URL' unless uri.is_a?(URI::HTTP)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                   open_timeout: 5, read_timeout: 5) do |http|
      http.request(Net::HTTP::Head.new(uri.request_uri))
    end

    # Cloudinary answers some delivery URLs with a redirect, so a 3xx is not by itself a
    # missing image -- follow it before calling the poster broken.
    if response.is_a?(Net::HTTPRedirection) && response['location'] && redirects.positive?
      return failure_for(URI.join(url, response['location']).to_s, redirects: redirects - 1)
    end

    return "HTTP #{response.code}" unless response.code.to_i == 200

    type = response['content-type'].to_s
    return "serves #{type.presence || 'no content type'}, not an image" unless type.start_with?('image/')

    nil
  rescue StandardError => e
    "#{e.class}: #{e.message.truncate(60)}"
  end
end
