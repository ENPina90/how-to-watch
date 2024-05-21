require 'csv'

class CsvExporterService
  def self.generate_seed_csv
    attributes = Entry.attribute_names
    CSV.generate(headers: true) do |csv|
      csv << (['seed', 'list_name'] + attributes) # Adding the header row
      Entry.includes(:list).find_each do |entry|
        list_name = entry.list.name
        row = [true, list_name]
        row << attributes.map { |attr| entry.send(attr) }
        csv << row.flatten
      end
    end
  end

  def self.generate_user_csv(entries)
    attributes = %w[list seen name alt year imdb source]
    CSV.generate(headers: true) do |csv|
      csv << attributes
      entries.includes(:list).sort_by(&:year).each do |entry|
        list_name = entry.list.name
        row = [list_name, entry.completed, entry.name, entry.alt, entry.year, entry.imdb]
        row << entry.source if entry.stream
        csv << row
      end
    end
  end
end
