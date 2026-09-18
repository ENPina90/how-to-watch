namespace :entry do
  desc "Check source for all entries"
  task check_sources: :environment do
    invalid_entries = []

    Entry.find_each do |entry|
      entry.check_source
      unless entry.stream
        invalid_entries << entry unless entry.stream
        puts "Entry ##{entry.id}: Source is invalid or unreachable."
      end
    end

    if invalid_entries.empty?
      puts "All entries have valid sources."
    else
      puts "\nInvalid Sources:"
      invalid_entries.each do |entry|
        puts "Entry ##{entry.name}: #{entry.source}"
      end
    end
  end

  # Asks MEGA's own API about every MEGA entry -- is the file there, and does the key in the
  # link open it -- and sets `stream` from the answer. See MegaAvailability.
  #
  # The page-title check that ran before could not judge MEGA at all and marked every MEGA
  # entry broken on arrival, which kept them all off the cable schedule. This is how that
  # gets undone, and how a MEGA link that has since died gets found.
  #
  # Dry run by default, the same as sources:backfill: it prints what would change and writes
  # nothing until APPLY=1. An entry MEGA did not answer about is left exactly as it is.
  # LIST=<id> narrows it to one channel.
  desc "Check every MEGA entry against MEGA's API and set stream from the answer (dry run unless APPLY=1)"
  task check_mega: :environment do
    apply = ENV["APPLY"] == "1"
    mega = Source.find_by(slug: "mega")
    abort "No MEGA source." unless mega

    scope = Entry.includes(:provider, list: :provider)
    scope = scope.where(list_id: ENV["LIST"]) if ENV["LIST"].present?
    entries = scope.select { |entry| MegaAvailability.applies_to?(entry) }
    puts "Asking MEGA about #{entries.size} entries..."

    results = MegaAvailability.new.for_entries(entries)
    changes = entries.filter_map do |entry|
      result = results.fetch(entry.id)
      next if result.unknown? || entry.stream == result.available?

      [entry, result]
    end

    states = results.values.map(&:state).tally
    puts "\nPlays:            #{states.fetch(:available, 0)}"
    puts "Will not play:    #{states.fetch(:missing, 0)}"
    puts "Not answered:     #{states.fetch(:unknown, 0)}  (left as they are)" if states[:unknown]

    if changes.empty?
      puts "\nEvery answered entry is already marked correctly."
      next
    end

    now_working, now_broken = changes.partition { |_, result| result.available? }
    puts "\nTo mark working: #{now_working.size}"
    puts "To mark broken:  #{now_broken.size}"
    now_broken.each do |entry, result|
      puts "  ##{entry.id} #{entry.name.to_s.truncate(40).ljust(42)} #{result.detail}"
    end

    if apply
      changes.each { |entry, result| entry.update_columns(stream: result.available?, updated_at: Time.current) }
      puts "\nWritten."
    else
      puts "\nNothing written. Re-run with APPLY=1 to write it."
    end
  end
end
