class CsvImporterService
  def self.import_from_csv(movie, user)
    list = List.find_or_create_by(name: movie[:list], user: user)
    existing_entry = Entry.find_by(imdb: movie[:imdb], list: list) ||
                      Entry.where('name ILIKE ?', movie[:title].strip).find_by(list: list)

    if existing_entry
      if existing_entry.update(completed: movie[:seen], name: movie[:title], alt: movie[:alt], imdb: movie[:imdb], source: movie[:source])
        message = "🔁 Updating: #{existing_entry.name} (#{existing_entry.year}) - already exists in list #{list.name}"
      else
        message = "❌ Skipping: no changes for #{existing_entry.name}"
      end
      Rails.logger.info(message)
      return message
    end
    imdb_id =  movie[:imdb] || OmdbApi.search_by_title(movie[:title], year: movie[:year])&.first
    unless imdb_id
      FailedEntry.create(name: movie["Title"], year: movie["Year"])
      return "Failed to fetch imdb_id for #{movie[:title]} (#{movie[:year]})"
    end
    omdb_result = OmdbApi.get_movie(imdb_id)
    return Entry.create_from_OMDB(omdb_result, list, movie[:seen] == "TRUE")
  end
end
