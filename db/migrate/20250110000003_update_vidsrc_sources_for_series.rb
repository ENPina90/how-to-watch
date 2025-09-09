class UpdateVidsrcSourcesForSeries < ActiveRecord::Migration[8.0]
  def up
    # Find all series entries with vidsrc sources
    entries_to_update = Entry.where(media: 'series')
                            .where("source ILIKE ?", '%vidsrc%')
                            .where.not(imdb: [nil, ''])

    entries_to_update.find_each do |entry|
      # Extract IMDb ID from the current source
      # Handle formats like: https://v2.vidsrc.me/embed/tt1213641
      imdb_match = entry.source.match(/embed\/(tt\d+)/)

      if imdb_match
        imdb_id = imdb_match[1]

        # Update the entry (bypass validations to avoid uniqueness conflicts)
        entry.update_columns(
          source_two: entry.source,  # Copy current source to source_two
          source: "https://vidsrc.cc/v3/embed/tv/#{imdb_id}"  # New source format
        )

        puts "Updated series entry #{entry.id} (#{entry.name}): #{entry.source_two} -> #{entry.source}"
      else
        puts "Could not extract IMDb ID from source for series entry #{entry.id} (#{entry.name}): #{entry.source}"
      end
    end

    puts "Migration completed. Updated #{entries_to_update.count} series entries."
  end

  def down
    # Revert the changes by moving source_two back to source
    entries_to_revert = Entry.where(media: 'series')
                            .where.not(source_two: [nil, ''])
                            .where("source ILIKE ?", '%vidsrc.cc%')

    entries_to_revert.find_each do |entry|
      entry.update_columns(
        source: entry.source_two,  # Move source_two back to source
        source_two: nil  # Clear source_two
      )

      puts "Reverted series entry #{entry.id} (#{entry.name}): #{entry.source}"
    end

    puts "Rollback completed. Reverted #{entries_to_revert.count} series entries."
  end
end
