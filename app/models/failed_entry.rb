class FailedEntry < ApplicationRecord
  def self.to_csv
    attributes = %w{List Seen Name Year IMDB} # CSV column names, added 'list_name'
    CSV.generate(headers: true) do |csv|
      csv << attributes # Adding the header row
      all.includes(:list).each do |entry|
        list_name = entry.list&.name || "No List" # Using safe navigation operator (&.) and providing a default
        csv << [list_name, entry.completed, entry.name, entry.year, entry.imdb]
      end
    end
  end
end
