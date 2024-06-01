require "faker"
require "csv"

# puts "Destroying all entries, lists, and users. In 3..2..1"
# sleep(3)
# FailedEntry.destroy_all
# Entry.destroy_all
# List.destroy_all
# User.destroy_all

# puts "Creating users..."
# User.create(email: "nic@gmail.com", password: "123456", username: "nic")
# User.create(email: "idk@gmail.com", password: "123456", username: "idk")

puts "Importing movies from CSV..."
CSV.foreach('db/seed_data/seeded_data.csv', headers: true, header_converters: :symbol) do |movie|
  user = User.first  # Assuming you want the first user for all entries, adjust as needed
  puts "Processing: #{movie[:title]} (#{movie[:year]})"

  entry_result = CsvImporterService.import_from_csv(movie, user)
  if entry_result.nil? && movie[:alt].present?
    movie[:title] = movie[:alt]
    entry_result = CsvImporterService.import_from_csv(movie, user)
  end
  if entry_result.instance_of?(Entry)
    puts "✅ Success: #{entry_result.name} (#{entry_result.year}) added to #{entry_result.list.name}"
  else
    puts entry_result
  end
  puts "-------------------------------------------------------------------------------------------"
end

Rake::Task['export:entries'].invoke
