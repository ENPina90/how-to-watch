class SimpleEpisodeFix < ActiveRecord::Migration[8.0]
  def up
    puts "=== SIMPLE EPISODE FIX ==="

    # Find all episode entries with vidsrc sources (simplified query)
    entries_to_update = Entry.where(media: 'episode')
                            .where("source ILIKE ?", '%vidsrc%')

    puts "Found #{entries_to_update.count} episode entries to process"

    updated_count = 0
    entries_to_update.find_each do |entry|
      # Skip if missing required fields
      next if entry.series_imdb.blank? || entry.season.blank? || entry.episode.blank?

      # Extract IMDb ID from the current source for logging
      imdb_match = entry.source.match(/embed\/(tt\d+)/)

      # Update the entry (bypass validations to avoid uniqueness conflicts)
      entry.update_columns(
        source_two: entry.source,  # Copy current source to source_two
        source: "https://vidsrc.cc/v3/embed/tv/#{entry.series_imdb}/#{entry.season}/#{entry.episode}"  # New source format using series_imdb
      )

      updated_count += 1
      puts "Updated episode entry #{entry.id} (#{entry.name}): #{entry.source_two} -> #{entry.source}" if updated_count <= 10
    end

    puts "Migration completed. Updated #{updated_count} episode entries."
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
