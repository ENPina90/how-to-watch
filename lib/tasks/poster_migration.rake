namespace :posters do
  desc "Migrate all entry pic URLs to Active Storage poster attachments"
  task migrate: :environment do
    start_time = Time.current
    puts "🔄 Starting poster migration from URLs to Active Storage..."
    puts "⏱️  This may take a while for large collections..."
    puts "💡 Each migration includes a small delay to respect server limits"
    puts ""

    service = PosterMigrationService.new
    results = service.migrate_all_posters(show_progress: true)

    duration = Time.current - start_time
    puts "\n⏱️  Migration completed in #{duration.round(2)} seconds"
    puts "\n📊 Migration Results:"
    puts "   Total entries processed: #{results[:total]}"
    puts "   ✅ Successfully migrated: #{results[:migrated]}"
    puts "   ⏭️  Skipped (already have poster): #{results[:skipped]}"
    puts "   ❌ Failed to migrate: #{results[:failed]}"
    puts "   💥 Errors: #{results[:errors]}"

    if results[:details].any?
      puts "\n📋 Detailed Results:"
      puts "-" * 80

      results[:details].each do |detail|
        puts "#{detail[:entry_name]} (ID: #{detail[:entry_id]})"
        puts "   Status: #{detail[:result][:status]}"
        puts "   Message: #{detail[:result][:message]}"
        if detail[:result][:old_url] && detail[:result][:filename]
          puts "   Source URL: #{detail[:result][:old_url]}"
          puts "   Filename: #{detail[:result][:filename]}"
        end
        puts ""
      end
    end

    puts "✨ Poster migration complete!"
  end

  desc "Migrate poster URLs for a specific list by ID"
  task :migrate_list, [:list_id] => :environment do |t, args|
    list_id = args[:list_id]

    if list_id.blank?
      puts "❌ Please provide a list ID: rails posters:migrate_list[123]"
      exit
    end

    begin
      list = List.find(list_id)
      start_time = Time.current
      puts "🔄 Starting poster migration for list: #{list.name}"
      puts "⏱️  This may take a while depending on list size..."
      puts ""

      service = PosterMigrationService.new
      results = service.migrate_list_posters(list_id, show_progress: true)

      duration = Time.current - start_time
      puts "\n⏱️  Migration completed in #{duration.round(2)} seconds"
      puts "\n📊 Migration Results for '#{list.name}':"
      puts "   Total entries processed: #{results[:total]}"
      puts "   ✅ Successfully migrated: #{results[:migrated]}"
      puts "   ⏭️  Skipped (already have poster): #{results[:skipped]}"
      puts "   ❌ Failed to migrate: #{results[:failed]}"
      puts "   💥 Errors: #{results[:errors]}"

      if results[:details].any?
        puts "\n📋 Detailed Results:"
        puts "-" * 50

        results[:details].each do |detail|
          puts "#{detail[:entry_name]} (ID: #{detail[:entry_id]})"
          puts "   Status: #{detail[:result][:status]}"
          puts "   Message: #{detail[:result][:message]}"
          if detail[:result][:filename]
            puts "   Filename: #{detail[:result][:filename]}"
          end
          puts ""
        end
      end

    rescue ActiveRecord::RecordNotFound
      puts "❌ List with ID #{list_id} not found"
    end
  end

  desc "Check how many entries need poster migration"
  task check: :environment do
    puts "🔍 Checking entries that need poster migration..."

    # Count entries with pic URLs but no poster attachments
    entries_needing_migration = Entry.where.not(pic: [nil, ""])
                                    .left_joins(:poster_attachment)
                                    .where(active_storage_attachments: { id: nil })

    total_with_pics = Entry.where.not(pic: [nil, ""]).count
    already_migrated = Entry.joins(:poster_attachment).count
    need_migration = entries_needing_migration.count

    puts "\n📊 Poster Migration Status:"
    puts "   Total entries with pic URLs: #{total_with_pics}"
    puts "   Already have poster attachments: #{already_migrated}"
    puts "   Need migration: #{need_migration}"

    if need_migration > 0
      puts "\n💡 Run 'rails posters:migrate' to migrate all entries"
      puts "💡 Or 'rails posters:migrate_list[ID]' for a specific list"
    else
      puts "\n✅ All entries with pic URLs already have poster attachments!"
    end
  end

  desc "Test migration for a single entry by ID"
  task :test_entry, [:entry_id] => :environment do |t, args|
    entry_id = args[:entry_id]

    if entry_id.blank?
      puts "❌ Please provide an entry ID: rails posters:test_entry[123]"
      exit
    end

    begin
      entry = Entry.find(entry_id)
      puts "🧪 Testing poster migration for: #{entry.name}"
      puts "📍 Current pic URL: #{entry.pic}"
      puts "📎 Has poster attachment: #{entry.poster.attached?}"
      puts ""

      service = PosterMigrationService.new
      result = service.migrate_entry_poster(entry)

      puts "📊 Migration Result:"
      puts "   Status: #{result[:status]}"
      puts "   Message: #{result[:message]}"
      if result[:filename]
        puts "   Filename: #{result[:filename]}"
      end

    rescue ActiveRecord::RecordNotFound
      puts "❌ Entry with ID #{entry_id} not found"
    end
  end

  desc "Show usage examples"
  task :help do
    puts <<~HELP
      🖼️  Poster Migration Tasks

      Available commands:

      📋 Check migration status:
         rails posters:check

      🔄 Migrate all entries:
         rails posters:migrate

      🎯 Migrate specific list:
         rails posters:migrate_list[123]

      🧪 Test single entry:
         rails posters:test_entry[456]

      ❓ Show this help:
         rails posters:help

      Note: Migration will download images from pic URLs and upload them
      to Cloudinary as Active Storage attachments. Original pic URLs are
      preserved for fallback purposes.

      Make sure your Cloudinary credentials are properly configured!
    HELP
  end
end
