require 'csv'

class CsvExporterService
  def self.generate_csv(entries)
    attributes = %w[list seen name alt year imdb source] # CSV column names, added 'list_name'
    CSV.generate(headers: true) do |csv|
      csv << attributes # Adding the header row
      entries.includes(:list).sort_by(&:year).each do |entry|
        list_name = entry.list.name
        row = [list_name, entry.completed, entry.name, entry.alt, entry.year, entry.imdb]
        row << entry.source if entry.stream
        csv << row
      end
    end
  end
end
