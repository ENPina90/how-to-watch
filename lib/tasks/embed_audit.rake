require "csv"

namespace :embeds do
  desc "List every entry VidSrc has no file for (LIST=<id> CSV=<path>)"
  task audit: :environment do
    scope = ENV["LIST"].present? ? Entry.where(list_id: ENV["LIST"]) : Entry.all

    counter = lambda do |done, total|
      print "\r[#{done}/#{total}] confirming..."
      $stdout.flush
    end

    puts "Screening against the VidSrc ID dumps..."

    begin
      result = EmbedAvailabilityAudit.new(scope: scope, progress: counter).call
    rescue EmbedAvailabilityAudit::CannotCheck => e
      # Reporting nothing beats reporting everything: see EmbedAvailabilityAudit.
      abort "Cannot check right now -- #{e.message}. Nothing has been reported."
    end

    puts ""
    puts "\nOn a VidSrc provider: #{result.checked}"
    puts "Doubted by the dumps:  #{result.suspected}"
    puts "Confirmed unplayable:  #{result.missing.size}"
    puts "Could not be asked:    #{result.unknown.size}" if result.unknown.any?
    puts "Nothing to ask about:  #{result.skipped}" if result.skipped.positive?

    if result.missing.empty?
      puts "\nEverything VidSrc was asked about, it has."
      next
    end

    puts "\nUnplayable, by channel:"
    result.missing.group_by { |row| row.entry.list }
          .sort_by { |list, rows| [-rows.size, list.name.to_s] }
          .each do |list, rows|
      puts "\n  #{list.name} (#{rows.size})"
      rows.sort_by { |row| row.entry.name.to_s }.each do |row|
        episode = row.lookup.season ? " S#{row.lookup.season}E#{row.lookup.episode}" : ""
        puts "    ##{row.entry.id} #{row.entry.name.to_s.truncate(40).ljust(42)} #{row.lookup.imdb}#{episode}"
        puts "      /entries/#{row.entry.id}/edit"
      end
    end

    path = Rails.root.join(ENV.fetch("CSV", "tmp/unplayable_embeds.csv"))
    CSV.open(path, "w") do |csv|
      csv << %w[entry_id name list media imdb episode provider edit_path]
      result.missing.sort_by { |row| [row.entry.list.name.to_s, row.entry.name.to_s] }.each do |row|
        episode = row.lookup.season ? "S#{row.lookup.season}E#{row.lookup.episode}" : nil
        csv << [row.entry.id, row.entry.name, row.entry.list.name, row.entry.media,
                row.lookup.imdb, episode, row.entry.resolved_source&.slug, "/entries/#{row.entry.id}/edit"]
      end
    end
    puts "\nWritten to #{path}"

    if result.unknown.any?
      puts "\nNot reported, because VidSrc did not answer for them:"
      result.unknown.first(10).each { |row| puts "  ##{row.entry.id} #{row.entry.name.to_s.truncate(40)} -- #{row.reason}" }
    end

    puts "\nThe weekly scan raises these as notifications; this task is the same check, on demand."
  end
end
