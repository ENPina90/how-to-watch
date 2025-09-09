class FixEpisodeSources < ActiveRecord::Migration[8.0]
  def up
    # Find all episode entries with vidsrc sources
    entries_to_update = Entry.where(media: 'episode')
                            .where("source ILIKE ?", '%vidsrc%')
                            .where.not(series_imdb: [nil, ''])
                            .where.not(season: [nil, ''])
                            .where.not(episode: [nil, ''])

    puts "Found #{entries_to_update.count} episode entries to update"

    entries_to_update.find_each do |entry|
      # Extract IMDb ID from the current source
      # Handle formats like: https://v2.vidsrc.me/embed/tt1213641/6-10
      imdb_match = entry.source.match(/embed\/(tt\d+)/)

      if imdb_match
        imdb_id = imdb_match[1]

        # Update the entry (bypass validations to avoid uniqueness conflicts)
        entry.update_columns(
          source_two: entry.source,  # Copy current source to source_two
          source: "https://vidsrc.cc/v3/embed/tv/#{entry.series_imdb}/#{entry.season}/#{entry.episode}"  # New source format using series_imdb
        )

        puts "Updated episode entry #{entry.id} (#{entry.name}): #{entry.source_two} -> #{entry.source}"
      else
        puts "Could not extract IMDb ID from source for episode entry #{entry.id} (#{entry.name}): #{entry.source}"
      end
    end

    puts "Migration completed. Updated #{entries_to_update.count} episode entries."
  end

  def down
    # Revert the changes by moving source_two back to source
    entries_to_revert = Entry.where(media: 'episode')
                            .where.not(source_two: [nil, ''])
                            .where("source ILIKE ?", '%vidsrc.cc%')

    entries_to_revert.find_each do |entry|
      entry.update_columns(
        source: entry.source_two,  # Move source_two back to source
        source_two: nil  # Clear source_two
      )

      puts "Reverted episode entry #{entry.id} (#{entry.name}): #{entry.source}"
    end

    puts "Rollback completed. Reverted #{entries_to_revert.count} episode entries."
  end
end
