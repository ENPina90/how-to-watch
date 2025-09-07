namespace :images do
  desc "Check all entries for broken image URLs and report them"
  task check: :environment do
    start_time = Time.current
    puts "🔍 Starting image validation check..."
    puts "⏱️  This may take a while for large collections..."
    puts ""

    service = ImageRepairService.new
    broken_entries = service.find_broken_images(show_progress: true)

    duration = Time.current - start_time
    puts "\n⏱️  Check completed in #{duration.round(2)} seconds"

    if broken_entries.empty?
      puts "✅ All images are working properly!"
    else
      puts "\n❌ Found #{broken_entries.count} entries with broken images:"
      puts "-" * 80

      broken_entries.each do |entry|
        puts "ID: #{entry[:id]} | #{entry[:name]}"
        puts "   Broken URL: #{entry[:pic]}"
        puts "   Has TMDB ID: #{entry[:has_tmdb] ? 'Yes' : 'No'} #{entry[:tmdb] if entry[:has_tmdb]}"
        puts ""
      end

      repairable = broken_entries.count { |e| e[:has_tmdb] }
      puts "📊 Summary:"
      puts "   Total broken: #{broken_entries.count}"
      puts "   Can be repaired (have TMDB ID): #{repairable}"
      puts "   Cannot be repaired (no TMDB ID): #{broken_entries.count - repairable}"
      puts ""
      puts "💡 Run 'rails images:repair' to fix the repairable ones"
    end
  end

  desc "Repair all broken entry images using TMDB API"
  task repair: :environment do
    start_time = Time.current
    puts "🔧 Starting image repair process..."
    puts "⏱️  This may take a while for large collections..."
    puts "💡 Each repair includes a small delay to respect TMDB API limits"
    puts ""

    service = ImageRepairService.new
    results = service.repair_all_images(show_progress: true)

    duration = Time.current - start_time
    puts "\n⏱️  Repair completed in #{duration.round(2)} seconds"
    puts "\n📊 Repair Results:"
    puts "   Total entries checked: #{results[:total]}"
    puts "   ✅ Already valid: #{results[:valid]}"
    puts "   🔧 Successfully repaired: #{results[:repaired]}"
    puts "   ⏭️  Skipped (no pic/ids): #{results[:skipped]}"
    puts "   ❌ Failed to repair: #{results[:failed]}"
    puts "   💥 Errors: #{results[:errors]}"

    # Show API source breakdown for repaired images
    if results[:repaired] > 0
      omdb_count = results[:details].count { |d| d[:result][:source] == "OMDB" }
      tmdb_count = results[:details].count { |d| d[:result][:source] == "TMDB" }
      series_count = results[:details].count { |d| d[:result][:source] == "OMDB Series" }
      puts "\n🔍 Repair Sources:"
      puts "   📺 OMDB API: #{omdb_count}" if omdb_count > 0
      puts "   🎬 TMDB API: #{tmdb_count}" if tmdb_count > 0
      puts "   📺 OMDB Series: #{series_count}" if series_count > 0
    end

    if results[:details].any?
      puts "\n📋 Detailed Results:"
      puts "-" * 80

              results[:details].each do |detail|
          puts "#{detail[:entry_name]} (ID: #{detail[:entry_id]})"
          puts "   Status: #{detail[:result][:status]}"
          puts "   Message: #{detail[:result][:message]}"
          if detail[:result][:old_url] && detail[:result][:new_url]
            puts "   Source: #{detail[:result][:source]}" if detail[:result][:source]
            puts "   Old URL: #{detail[:result][:old_url]}"
            puts "   New URL: #{detail[:result][:new_url]}"
          end
          puts ""
        end
    end

    puts "✨ Image repair complete!"
  end

  desc "Repair images for a specific list by ID"
  task :repair_list, [:list_id] => :environment do |t, args|
    list_id = args[:list_id]

    if list_id.blank?
      puts "❌ Please provide a list ID: rails images:repair_list[123]"
      exit
    end

    begin
      list = List.find(list_id)
      start_time = Time.current
      puts "🔧 Starting repair for list: #{list.name}"
      puts "⏱️  This may take a while depending on list size..."
      puts ""

      service = ImageRepairService.new
      results = service.repair_list_images(list_id, show_progress: true)

      duration = Time.current - start_time
      puts "\n⏱️  Repair completed in #{duration.round(2)} seconds"
      puts "\n📊 Repair Results for '#{list.name}':"
      puts "   Total entries checked: #{results[:total]}"
      puts "   ✅ Already valid: #{results[:valid]}"
      puts "   🔧 Successfully repaired: #{results[:repaired]}"
      puts "   ⏭️  Skipped (no pic/ids): #{results[:skipped]}"
      puts "   ❌ Failed to repair: #{results[:failed]}"
      puts "   💥 Errors: #{results[:errors]}"

      # Show API source breakdown for repaired images
      if results[:repaired] > 0
        omdb_count = results[:details].count { |d| d[:result][:source] == "OMDB" }
        tmdb_count = results[:details].count { |d| d[:result][:source] == "TMDB" }
        puts "\n🔍 Repair Sources:"
        puts "   📺 OMDB API: #{omdb_count}" if omdb_count > 0
        puts "   🎬 TMDB API: #{tmdb_count}" if tmdb_count > 0
      end

      if results[:details].any?
        puts "\n📋 Detailed Results:"
        puts "-" * 50

        results[:details].each do |detail|
          puts "#{detail[:entry_name]} (ID: #{detail[:entry_id]})"
          puts "   Status: #{detail[:result][:status]}"
          puts "   Message: #{detail[:result][:message]}"
          puts "   Source: #{detail[:result][:source]}" if detail[:result][:source]
          puts ""
        end
      end

    rescue ActiveRecord::RecordNotFound
      puts "❌ List with ID #{list_id} not found"
    end
  end

  desc "Test image validation for a specific URL"
  task :test_url, [:url] => :environment do |t, args|
    url = args[:url]

    if url.blank?
      puts "❌ Please provide a URL: rails images:test_url['https://example.com/image.jpg']"
      exit
    end

    puts "🧪 Testing image URL: #{url}"

    service = TmdbService.new
    is_valid = service.validate_image_url(url)

    if is_valid
      puts "✅ Image URL is valid and accessible"
    else
      puts "❌ Image URL is broken or inaccessible"
    end
  end

  desc "Show usage examples"
  task :help do
    puts <<~HELP
      🖼️  Image Repair Tasks

      Available commands:

      📋 Check for broken images:
         rails images:check

      🔧 Repair all broken images:
         rails images:repair

      🎯 Repair images for specific list:
         rails images:repair_list[123]

      🧪 Test a specific URL:
         rails images:test_url['https://example.com/image.jpg']

      ❓ Show this help:
         rails images:help

      Note: Repair tasks use a 3-tier approach:
      1. Try OMDB API with entry's IMDB ID
      2. Try TMDB API with entry's TMDB ID
      3. Try OMDB API with entry's Series IMDB ID (for episodes)

      Make sure your OMDB_API_KEY and TMDB_API_KEY environment variables are set.
    HELP
  end
end
