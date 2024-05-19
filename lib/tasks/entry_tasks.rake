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
end
