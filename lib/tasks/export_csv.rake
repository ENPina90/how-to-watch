namespace :export do
  desc "Export entries to a CSV file"
  task entries: :environment do
    relative_path = Rails.root.join('db', 'seed_data', 'seeded_data.csv')
    File.write(relative_path, CsvExporterService.generate_seed_csv)
    puts "Entries have been exported to CSV."
  end
end
