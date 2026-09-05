require "csv"

namespace :posters do
  desc "List every entry whose poster does not load (LIST=<id> CSV=<path> CONCURRENCY=<n>)"
  task audit: :environment do
    include ImageHelper

    scope = Entry.includes(:list, poster_attachment: :blob)
    scope = scope.where(list_id: ENV["LIST"]) if ENV["LIST"].present?

    # The URLs are collected up front, in one pass, so the checks below can run on threads
    # without every one of them reaching for a database connection: the pool is five wide
    # and the checks are a dozen.
    targets = scope.map do |entry|
      { entry: entry, url: entry_poster_url(entry).presence }
    end

    puts "Checking #{targets.size} posters..."

    broken = PosterAudit.new(concurrency: ENV.fetch("CONCURRENCY", 12).to_i).call(targets)

    puts "\nEntries:         #{targets.size}"
    puts "Posters loading: #{targets.size - broken.size}"
    puts "Broken:          #{broken.size}"

    if broken.empty?
      puts "\nEvery poster loads."
      next
    end

    # Grouped by channel because that is how they get fixed: you open one list and work
    # down it, rather than jumping between lists an entry at a time.
    puts "\nBroken posters, by channel:"
    broken.group_by { |row| row[:entry].list }.sort_by { |list, rows| [-rows.size, list.name.to_s] }.each do |list, rows|
      puts "\n  #{list.name} (#{rows.size})"
      rows.sort_by { |row| row[:entry].name.to_s }.each do |row|
        entry = row[:entry]
        puts "    ##{entry.id} #{entry.name.to_s.truncate(48).ljust(48)} #{row[:reason]}"
        puts "      /entries/#{entry.id}/edit"
      end
    end

    path = Rails.root.join(ENV.fetch("CSV", "tmp/broken_posters.csv"))
    CSV.open(path, "w") do |csv|
      csv << %w[entry_id name list media source reason url edit_path]
      broken.sort_by { |row| [row[:entry].list.name.to_s, row[:entry].name.to_s] }.each do |row|
        entry = row[:entry]
        csv << [entry.id, entry.name, entry.list.name, entry.media, row[:source],
                row[:reason], row[:url], "/entries/#{entry.id}/edit"]
      end
    end
    puts "\nWritten to #{path}"

    repairable = broken.count { |row| row[:entry].imdb.present? || row[:entry].tmdb.present? || row[:entry].series_imdb.present? }
    puts "#{repairable} of them carry an IMDB/TMDB id, so `rails images:repair` can try them first."
  end
end

# Asks each poster URL whether it is really there. Kept out of ImageRepairService, which
# only ever looks at `pic` and repairs as it goes: this reports on what the page actually
# renders -- an attached poster included -- and changes nothing.
class PosterAudit
  REDIRECT_LIMIT = 3

  def initialize(concurrency: 12)
    @concurrency = concurrency
  end

  # Returns one row per target that will not render, in the order they were given.
  def call(targets)
    queue = Queue.new
    targets.each_with_index { |target, index| queue << [index, target] }

    results = Array.new(targets.size)
    mutex = Mutex.new
    finished = 0

    workers = Array.new([@concurrency, targets.size].min) do
      Thread.new do
        while (job = queue.pop(true) rescue nil)
          index, target = job
          results[index] = examine(target)
          mutex.synchronize do
            finished += 1
            print "\r[#{finished}/#{targets.size}]" if (finished % 25).zero? || finished == targets.size
            $stdout.flush
          end
        end
      end
    end
    workers.each(&:join)
    puts ""

    results.compact
  end

  private

  def examine(target)
    entry = target[:entry]
    source = entry.poster.attached? ? "poster" : "pic"

    # Nothing to point the tag at: these render as an empty frame with the alt text in it,
    # which is what a missing poster looks like on the channel row.
    return row(target, source, "no image on the entry") if target[:url].blank?

    reason = failure_for(target[:url])
    reason && row(target, source, reason)
  end

  def row(target, source, reason)
    { entry: target[:entry], url: target[:url], source: source, reason: reason }
  end

  # nil when the URL serves an image, a short description of the problem otherwise.
  def failure_for(url, redirects: REDIRECT_LIMIT)
    # A handful of entries carry the image inline rather than linking to it. There is
    # nothing to request, and the browser renders it, so it is not broken.
    return nil if url.start_with?("data:image/")

    uri = URI.parse(url)
    return "not an http(s) URL" unless uri.is_a?(URI::HTTP)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: 5, read_timeout: 5) do |http|
      http.request(Net::HTTP::Head.new(uri.request_uri))
    end

    # Cloudinary answers some delivery URLs with a redirect, so a 3xx is not by itself a
    # missing image -- follow it before calling the poster broken.
    if response.is_a?(Net::HTTPRedirection) && response["location"] && redirects.positive?
      return failure_for(URI.join(url, response["location"]).to_s, redirects: redirects - 1)
    end

    return "HTTP #{response.code}" unless response.code.to_i == 200

    type = response["content-type"].to_s
    return "serves #{type.presence || 'no content type'}, not an image" unless type.start_with?("image/")

    nil
  rescue StandardError => e
    "#{e.class}: #{e.message.truncate(60)}"
  end
end
