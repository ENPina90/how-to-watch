namespace :export do
  desc "Export entries to a CSV file"
  task entries: :environment do
    File.write('/Users/nicholaspina/code/how-to-watch/db/seed_data/seeded_movies.csv', Entry.to_csv)
    puts "Entries have been exported to CSV."
  end
end
