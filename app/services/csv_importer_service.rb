class CsvImporterService
  def self.import_from_csv(entry, user)
    list = List.find_or_create_by(name: entry[:list_name], user: user)
    existing_entry = Entry.find_by(imdb: entry[:imdb], list: list) &&
                     Entry.where('name ILIKE ?', entry[:name].strip).find_by(list: list)
    if existing_entry
      entry_attributes = entry.to_hash.except(:list_name, :seed, :seen)
      existing_entry.assign_attributes(entry_attributes)
      if existing_entry.changed?
        message = "#{existing_entry.save ? '🔁 Updating:' : '❌ Failed to update:'} #{existing_entry.name}"
      else
        message = "⏭️ Skipping: no changes for #{existing_entry.name}"
      end

      Rails.logger.info(message)
      return message
    end
    entry = omdb_api(entry) unless entry[:seed]
    seen = entry[:seen]&.downcase == "true"
    Entry.create_from_source(entry, list, seen)
  end

  def self.omdb_api(entry)
    imdb_id = entry[:imdb] || OmdbApi.search_by_title(entry[:name], year: entry[:year])&.first
    unless imdb_id
      FailedEntry.create(name: entry["name"], year: entry["year"])
      return "Failed to fetch imdb_id for #{entry[:name]} (#{entry[:year]})"
    end
    omdb_result = OmdbApi.get_movie(imdb_id)
    OmdbApi.normalize_omdb_data(omdb_result)
  end
end
