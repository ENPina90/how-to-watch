namespace :tmdb do
  desc 'Fetch trailers for all entries using their TMDb ID and save them to the database'
  task update_trailers: :environment do
    # Loop through all entries that have a tmdb ID but no trailer URL yet
    Entry.where.not(tmdb: nil).find_each do |entry|
      # Use the TmdbService to fetch the trailer URL
      tmdb_service = TmdbService.new
      trailer_url = tmdb_service.fetch_trailer_url(entry)

      if trailer_url
        # Save the trailer URL to the entry
        entry.update(trailer: trailer_url)
        puts "Updated Entry ##{entry.id} with trailer URL: #{trailer_url}"
      else
        puts "No trailer found for Entry ##{entry.id}"
      end
    end
  end
end
