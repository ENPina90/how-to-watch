require "csv"

namespace :posters do
  desc "List every entry whose poster does not load (LIST=<id> CSV=<path> CONCURRENCY=<n>)"
  task audit: :environment do
    scope = ENV["LIST"].present? ? Entry.where(list_id: ENV["LIST"]) : Entry.all

    counter = lambda do |done, total|
      print "\r[#{done}/#{total}]" if (done % 25).zero? || done == total
      $stdout.flush
    end

    puts "Checking #{scope.count} posters..."
    result = PosterAudit.new(scope: scope, concurrency: ENV.fetch("CONCURRENCY", PosterAudit::DEFAULT_CONCURRENCY).to_i,
                             progress: counter).call
    broken = result.broken
    puts ""

    puts "\nEntries:         #{result.checked}"
    puts "Posters loading: #{result.checked - broken.size}"
    puts "Broken:          #{broken.size}"

    if broken.empty?
      puts "\nEvery poster loads."
      next
    end

    # Grouped by channel because that is how they get fixed: you open one list and work
    # down it, rather than jumping between lists an entry at a time.
    puts "\nBroken posters, by channel:"
    broken.group_by { |row| row.entry.list }.sort_by { |list, rows| [-rows.size, list.name.to_s] }.each do |list, rows|
      puts "\n  #{list.name} (#{rows.size})"
      rows.sort_by { |row| row.entry.name.to_s }.each do |row|
        puts "    ##{row.entry.id} #{row.entry.name.to_s.truncate(48).ljust(48)} #{row.reason}"
        puts "      /entries/#{row.entry.id}/edit"
      end
    end

    path = Rails.root.join(ENV.fetch("CSV", "tmp/broken_posters.csv"))
    CSV.open(path, "w") do |csv|
      csv << %w[entry_id name list media source reason url edit_path]
      broken.sort_by { |row| [row.entry.list.name.to_s, row.entry.name.to_s] }.each do |row|
        csv << [row.entry.id, row.entry.name, row.entry.list.name, row.entry.media, row.source,
                row.reason, row.url, "/entries/#{row.entry.id}/edit"]
      end
    end
    puts "\nWritten to #{path}"

    repairable = broken.count { |row| row.entry.imdb.present? || row.entry.tmdb.present? || row.entry.series_imdb.present? }
    puts "#{repairable} of them carry an IMDB/TMDB id, so `rails images:repair` can try them first."
    puts "The weekly scan raises these as notifications; this task is the same check, on demand."
  end
end
