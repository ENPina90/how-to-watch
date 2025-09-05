require 'open-uri'

class PosterMigrationService
  def initialize
    @tmdb_service = TmdbService.new
  end

  # Migrate a single entry's pic URL to Active Storage poster
  def migrate_entry_poster(entry)
    return { status: :skipped, message: "Entry already has poster attached" } if entry.poster.attached?
    return { status: :skipped, message: "Entry has no pic URL" } if entry.pic.blank?

    begin
      # Validate the URL before attempting to download
      unless @tmdb_service.validate_image_url(entry.pic)
        return { status: :failed, message: "Pic URL is not accessible" }
      end

      # Download and attach the image
      downloaded_image = URI.open(entry.pic)
      filename = extract_filename_from_url(entry.pic)
      content_type = extract_content_type(entry.pic, downloaded_image)

      entry.poster.attach(
        io: downloaded_image,
        filename: filename,
        content_type: content_type
      )

      {
        status: :migrated,
        message: "Successfully migrated pic URL to poster attachment",
        old_url: entry.pic,
        filename: filename
      }

    rescue OpenURI::HTTPError => e
      { status: :failed, message: "HTTP error downloading image: #{e.message}" }
    rescue StandardError => e
      { status: :error, message: "Error migrating poster: #{e.message}" }
    end
  end

  # Migrate all entries without poster attachments
  def migrate_all_posters(show_progress: false)
    results = {
      total: 0,
      migrated: 0,
      skipped: 0,
      failed: 0,
      errors: 0,
      details: []
    }

    entries = Entry.where.not(pic: [nil, ""])
                  .left_joins(:poster_attachment)
                  .where(active_storage_attachments: { id: nil })

    total_count = entries.count

    puts "🔄 Found #{total_count} entries with pic URLs but no poster attachments..." if show_progress

    entries.find_each.with_index do |entry, index|
      results[:total] += 1

      if show_progress
        progress = ((index + 1).to_f / total_count * 100).round(1)
        print "\r[#{index + 1}/#{total_count}] (#{progress}%) Migrating: #{entry.name.truncate(50)}..."
        $stdout.flush
      end

      result = migrate_entry_poster(entry)

      # Safely increment result counter
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
      if show_progress && result[:status] != :skipped
        puts ""  # New line after progress
        case result[:status]
        when :migrated
          puts "   ✅ MIGRATED: #{entry.name} -> #{result[:filename]}"
        when :failed
          puts "   ❌ FAILED: #{entry.name} - #{result[:message]}"
        when :error
          puts "   💥 ERROR: #{entry.name} - #{result[:message]}"
        end
      end

      # Log detailed results for non-skipped entries
      unless result[:status] == :skipped
        results[:details] << {
          entry_id: entry.id,
          entry_name: entry.name,
          result: result
        }
      end

      # Add small delay to be respectful to servers
      sleep(0.1) if result[:status] == :migrated
    end

    puts "" if show_progress  # Final newline
    results
  end

  # Migrate posters for a specific list
  def migrate_list_posters(list_id, show_progress: false)
    results = {
      total: 0,
      migrated: 0,
      skipped: 0,
      failed: 0,
      errors: 0,
      details: []
    }

    list = List.find(list_id)
    entries_to_migrate = list.entries.where.not(pic: [nil, ""])
                              .left_joins(:poster_attachment)
                              .where(active_storage_attachments: { id: nil })

    total_count = entries_to_migrate.count

    puts "🔄 Found #{total_count} entries in '#{list.name}' to migrate..." if show_progress

    entries_to_migrate.find_each.with_index do |entry, index|
      results[:total] += 1

      if show_progress
        progress = ((index + 1).to_f / total_count * 100).round(1)
        print "\r[#{index + 1}/#{total_count}] (#{progress}%) Migrating: #{entry.name.truncate(50)}..."
        $stdout.flush
      end

      result = migrate_entry_poster(entry)

      # Safely increment result counter
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
      if show_progress && result[:status] != :skipped
        puts ""  # New line after progress
        case result[:status]
        when :migrated
          puts "   ✅ MIGRATED: #{entry.name} -> #{result[:filename]}"
        when :failed
          puts "   ❌ FAILED: #{entry.name} - #{result[:message]}"
        when :error
          puts "   💥 ERROR: #{entry.name} - #{result[:message]}"
        end
      end

      unless result[:status] == :skipped
        results[:details] << {
          entry_id: entry.id,
          entry_name: entry.name,
          result: result
        }
      end

      sleep(0.1) if result[:status] == :migrated
    end

    puts "" if show_progress  # Final newline
    results
  end

  private

  def extract_filename_from_url(url)
    # Extract filename from URL, or generate one
    uri = URI.parse(url)
    filename = File.basename(uri.path)

    # If no filename or extension, generate one
    if filename.blank? || !filename.include?('.')
      timestamp = Time.current.to_i
      "poster_#{timestamp}.jpg"
    else
      filename
    end
  rescue StandardError
    "poster_#{Time.current.to_i}.jpg"
  end

  def extract_content_type(url, downloaded_image = nil)
    # Try to determine content type from URL extension
    extension = File.extname(URI.parse(url).path).downcase

    case extension
    when '.jpg', '.jpeg'
      'image/jpeg'
    when '.png'
      'image/png'
    when '.gif'
      'image/gif'
    when '.webp'
      'image/webp'
    else
      # Default to JPEG if we can't determine
      'image/jpeg'
    end
  rescue StandardError
    'image/jpeg'
  end
end
