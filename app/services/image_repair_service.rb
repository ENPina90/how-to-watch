class ImageRepairService
  def initialize
    @tmdb_service = TmdbService.new
  end

  # Check and repair a single entry's image
  def repair_entry_image(entry)
    return { status: :skipped, message: "Entry has no pic URL" } if entry.pic.blank?
    return { status: :skipped, message: "Entry has no IMDB, TMDB, or Series IMDB ID" } if entry.imdb.blank? && entry.tmdb.blank? && entry.series_imdb.blank?

    # Check if current image URL is valid
    if @tmdb_service.validate_image_url(entry.pic)
      return { status: :valid, message: "Image URL is working" }
    end

    # Current image is broken, try to get a new one
    new_poster_url = nil
    source = nil

    # First, try OMDB API if we have an IMDB ID
    if entry.imdb.present?
      new_poster_url = @tmdb_service.fetch_omdb_poster_url(entry.imdb)
      source = "OMDB" if new_poster_url
    end

    # If OMDB didn't work, try TMDB API if we have a TMDB ID
    if new_poster_url.nil? && entry.tmdb.present?
      new_poster_url = @tmdb_service.fetch_poster_url(entry.tmdb, entry.media)
      source = "TMDB" if new_poster_url
    end

    # Last resort: try series poster from OMDB if this is an episode/series entry
    if new_poster_url.nil? && entry.series_imdb.present?
      new_poster_url = @tmdb_service.fetch_omdb_poster_url(entry.series_imdb)
      source = "OMDB Series" if new_poster_url
    end

    if new_poster_url
      old_url = entry.pic
      entry.update!(pic: new_poster_url)
      {
        status: :repaired,
        message: "Replaced broken image with #{source} poster",
        old_url: old_url,
        new_url: new_poster_url,
        source: source
      }
    else
      missing_ids = []
      missing_ids << "IMDB" if entry.imdb.blank?
      missing_ids << "TMDB" if entry.tmdb.blank?
      missing_ids << "Series IMDB" if entry.series_imdb.blank?

      if missing_ids.length == 3
        {
          status: :failed,
          message: "Could not find replacement image. Missing all IDs: #{missing_ids.join(', ')}"
        }
      else
        {
          status: :failed,
          message: "Could not find replacement image on OMDB, TMDB, or Series OMDB"
        }
      end
    end
  rescue StandardError => e
    {
      status: :error,
      message: "Error processing entry: #{e.message}"
    }
  end

  # Repair images for all entries
  def repair_all_images(show_progress: false)
    results = {
      total: 0,
      valid: 0,
      repaired: 0,
      failed: 0,
      skipped: 0,
      errors: 0,
      details: []
    }

    entries = Entry.where.not(pic: [nil, ""]).where(
      "imdb IS NOT NULL AND imdb != '' OR tmdb IS NOT NULL AND tmdb != '' OR series_imdb IS NOT NULL AND series_imdb != ''"
    )
    total_count = entries.count

    puts "🔍 Found #{total_count} entries with images and IMDB/TMDB/Series IMDB IDs to check..." if show_progress

    entries.find_each.with_index do |entry, index|
      results[:total] += 1

      if show_progress
        progress = ((index + 1).to_f / total_count * 100).round(1)
        print "\r[#{index + 1}/#{total_count}] (#{progress}%) Checking: #{entry.name.truncate(50)}..."
        $stdout.flush
      end

      result = repair_entry_image(entry)

      # Safely increment result counter, handling unexpected results
      if result.is_a?(Hash) && result[:status]
        status = result[:status]
        if results.key?(status)
          results[status] += 1
        else
          puts "\nWarning: Unexpected status '#{status}' for entry #{entry.name}" if show_progress
          results[:errors] += 1
        end
      else
        puts "\nError: Invalid result format for entry #{entry.name}: #{result.inspect}" if show_progress
        results[:errors] += 1
        result = { status: :error, message: "Invalid result format" }
      end

      # Show immediate feedback for important actions
      if show_progress && result[:status] != :valid
        puts ""  # New line after progress
        case result[:status]
        when :repaired
          puts "   ✅ REPAIRED: #{entry.name} (using #{result[:source]})"
        when :failed
          puts "   ❌ FAILED: #{entry.name} - #{result[:message]}"
        when :skipped
          puts "   ⏭️  SKIPPED: #{entry.name} - #{result[:message]}"
        when :error
          puts "   💥 ERROR: #{entry.name} - #{result[:message]}"
        end
      end

      # Log detailed results for non-valid entries
      unless result[:status] == :valid
        results[:details] << {
          entry_id: entry.id,
          entry_name: entry.name,
          result: result
        }
      end

      # Add some delay to be respectful to TMDB API
      sleep(0.1) if result[:status] == :repaired
    end

    puts "" if show_progress  # Final newline
    results
  end

  # Find entries with broken images (for reporting without fixing)
  def find_broken_images(show_progress: false)
    broken_entries = []
    entries = Entry.where.not(pic: [nil, ""])
    total_count = entries.count

    puts "🔍 Checking #{total_count} entries for broken images..." if show_progress

    entries.find_each.with_index do |entry, index|
      if show_progress
        progress = ((index + 1).to_f / total_count * 100).round(1)
        print "\r[#{index + 1}/#{total_count}] (#{progress}%) Checking: #{entry.name.truncate(50)}..."
        $stdout.flush
      end

      unless @tmdb_service.validate_image_url(entry.pic)
        broken_entries << {
          id: entry.id,
          name: entry.name,
          pic: entry.pic,
          tmdb: entry.tmdb,
          has_tmdb: entry.tmdb.present?
        }

        if show_progress
          puts ""  # New line
          puts "   ❌ BROKEN: #{entry.name}"
        end
      end

      # Add small delay to avoid overwhelming servers
      sleep(0.05)
    end

    puts "" if show_progress  # Final newline
    broken_entries
  end

  # Repair images for a specific list
  def repair_list_images(list_id, show_progress: false)
    results = {
      total: 0,
      valid: 0,
      repaired: 0,
      failed: 0,
      skipped: 0,
      errors: 0,
      details: []
    }

    list = List.find(list_id)
    entries_to_check = list.entries.where.not(pic: [nil, ""]).where(
      "imdb IS NOT NULL AND imdb != '' OR tmdb IS NOT NULL AND tmdb != '' OR series_imdb IS NOT NULL AND series_imdb != ''"
    )
    total_count = entries_to_check.count

    puts "🔍 Found #{total_count} entries in '#{list.name}' with images and IMDB/TMDB/Series IMDB IDs to check..." if show_progress

    entries_to_check.find_each.with_index do |entry, index|
      results[:total] += 1

      if show_progress
        progress = ((index + 1).to_f / total_count * 100).round(1)
        print "\r[#{index + 1}/#{total_count}] (#{progress}%) Checking: #{entry.name.truncate(50)}..."
        $stdout.flush
      end

      result = repair_entry_image(entry)

      # Safely increment result counter, handling unexpected results
      if result.is_a?(Hash) && result[:status]
        status = result[:status]
        if results.key?(status)
          results[status] += 1
        else
          puts "\nWarning: Unexpected status '#{status}' for entry #{entry.name}" if show_progress
          results[:errors] += 1
        end
      else
        puts "\nError: Invalid result format for entry #{entry.name}: #{result.inspect}" if show_progress
        results[:errors] += 1
        result = { status: :error, message: "Invalid result format" }
      end

      # Show immediate feedback for important actions
      if show_progress && result[:status] != :valid
        puts ""  # New line after progress
        case result[:status]
        when :repaired
          puts "   ✅ REPAIRED: #{entry.name} (using #{result[:source]})"
        when :failed
          puts "   ❌ FAILED: #{entry.name} - #{result[:message]}"
        when :skipped
          puts "   ⏭️  SKIPPED: #{entry.name} - #{result[:message]}"
        when :error
          puts "   💥 ERROR: #{entry.name} - #{result[:message]}"
        end
      end

      unless result[:status] == :valid
        results[:details] << {
          entry_id: entry.id,
          entry_name: entry.name,
          result: result
        }
      end

      sleep(0.1) if result[:status] == :repaired
    end

    puts "" if show_progress  # Final newline
    results
  end
end
