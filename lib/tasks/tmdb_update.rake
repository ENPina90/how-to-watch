# lib/tasks/tmdb_update.rake
namespace :tmdb do
  desc 'Fetch TMDB IDs for all entries using their IMDb ID'
  task update_tmdb_ids: :environment do
    require 'themoviedb-api'

    Entry.where.not(imdb: nil).find_each do |entry|
      imdb_id = entry.imdb

      # Search TMDb by IMDb ID
      begin
        tmdb_id = Tmdb::Movie.detail(imdb_id).id

        # if tmdb_result['movie_results'].present?
        #   tmdb_id = tmdb_result['movie_results'].first['id']
        # elsif tmdb_result['tv_results'].present?
        #   tmdb_id = tmdb_result['tv_results'].first['id']
        # else
        #   puts "No TMDb entry found for IMDb ID: #{imdb_id}"
        #   next
        # end

        # Update the entry with the fetched TMDb ID
        entry.update(tmdb: tmdb_id)
        puts "Updated entry ##{entry.id} with TMDb ID: #{tmdb_id}"

      rescue StandardError => e
        puts "Error fetching TMDb ID for IMDb ID #{imdb_id}: #{e.message}"
      end
    end
  end
end
