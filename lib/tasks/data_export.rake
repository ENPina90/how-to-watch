namespace :data do
  desc "Export all data including Active Storage attachments for production deployment"
  task export_for_production: :environment do
    puts "📦 Exporting development data for production deployment..."
    puts "⏱️  This includes all entries, lists, users, and Active Storage attachments"
    puts ""

    export_dir = Rails.root.join('tmp', 'production_export')
    FileUtils.mkdir_p(export_dir)

    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")

    # Export database structure and data
    puts "🗄️  Exporting database..."
    db_config = Rails.configuration.database_configuration[Rails.env]
    db_file = export_dir.join("database_#{timestamp}.sql")

    system("pg_dump -h #{db_config['host'] || 'localhost'} -U #{db_config['username']} -d #{db_config['database']} > #{db_file}")

    # Export Active Storage blob information
    puts "📎 Exporting Active Storage blob data..."
    blob_data = {
      blobs: [],
      attachments: [],
      export_timestamp: timestamp,
      cloudinary_folder: Rails.application.config.active_storage.service == :cloudinary ? 'development' : nil
    }

    ActiveStorage::Blob.includes(:attachments).each do |blob|
      blob_data[:blobs] << {
        id: blob.id,
        key: blob.key,
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        metadata: blob.metadata,
        service_name: blob.service_name,
        byte_size: blob.byte_size,
        checksum: blob.checksum,
        created_at: blob.created_at
      }

      blob.attachments.each do |attachment|
        blob_data[:attachments] << {
          id: attachment.id,
          name: attachment.name,
          record_type: attachment.record_type,
          record_id: attachment.record_id,
          blob_id: attachment.blob_id,
          created_at: attachment.created_at
        }
      end
    end

    blob_file = export_dir.join("active_storage_#{timestamp}.json")
    File.write(blob_file, JSON.pretty_generate(blob_data))

    # Export Cloudinary asset list
    puts "☁️  Cataloging Cloudinary assets..."
    cloudinary_assets = []

    ActiveStorage::Blob.where(service_name: 'cloudinary').each do |blob|
      cloudinary_assets << {
        blob_key: blob.key,
        filename: blob.filename.to_s,
        cloudinary_public_id: "development/#{blob.key}",  # Assuming development folder
        byte_size: blob.byte_size,
        content_type: blob.content_type
      }
    end

    cloudinary_file = export_dir.join("cloudinary_assets_#{timestamp}.json")
    File.write(cloudinary_file, JSON.pretty_generate(cloudinary_assets))

    # Create import instructions
    instructions = <<~INSTRUCTIONS
      # Production Deployment Instructions

      ## Files Generated:
      - database_#{timestamp}.sql: Full database dump
      - active_storage_#{timestamp}.json: Active Storage blob/attachment data
      - cloudinary_assets_#{timestamp}.json: Cloudinary asset catalog

      ## Production Import Steps:

      1. **Setup Cloudinary Environment:**
         Make sure production uses the same Cloudinary credentials:
         ```
         CLOUDINARY_CLOUD_NAME=#{ENV['CLOUDINARY_CLOUD_NAME']}
         CLOUDINARY_API_KEY=#{ENV['CLOUDINARY_API_KEY']}
         CLOUDINARY_API_SECRET=[your_secret]
         ```

      2. **Choose Cloudinary Folder Strategy:**

         Option A - Shared Folder (Recommended):
         Update config/storage.yml:
         ```yaml
         cloudinary:
           service: Cloudinary
           folder: shared  # Same folder for dev/prod
         ```

         Option B - Environment Folders:
         Keep current setup and copy assets in Cloudinary from 'development' to 'production'

      3. **Import Database:**
         ```bash
         # In production
         psql your_production_db < database_#{timestamp}.sql
         ```

      4. **Verify Active Storage:**
         ```bash
         rails console
         # Test that attachments work
         Entry.joins(:poster_attachment).first.poster.attached?
         ```

      ## Verification Commands:
      ```bash
      rails data:verify_import
      ```

      ## Cloudinary Assets:
      #{cloudinary_assets.count} assets catalogued for reference

      Generated at: #{Time.current}
    INSTRUCTIONS

    instructions_file = export_dir.join("IMPORT_INSTRUCTIONS.md")
    File.write(instructions_file, instructions)

    puts "\n✅ Export completed successfully!"
    puts "📁 Files saved to: #{export_dir}"
    puts "📋 Database dump: #{db_file.basename}"
    puts "📎 Active Storage data: #{blob_file.basename}"
    puts "☁️  Cloudinary catalog: #{cloudinary_file.basename}"
    puts "📖 Instructions: #{instructions_file.basename}"
    puts ""
    puts "🚀 Ready for production deployment!"
    puts "📖 See IMPORT_INSTRUCTIONS.md for deployment steps"
  end

  desc "Verify Active Storage integrity after import"
  task verify_import: :environment do
    puts "🔍 Verifying Active Storage integrity after import..."

    total_entries = Entry.count
    entries_with_posters = Entry.joins(:poster_attachment).count
    broken_attachments = 0

    puts "📊 Statistics:"
    puts "   Total entries: #{total_entries}"
    puts "   Entries with poster attachments: #{entries_with_posters}"

    # Test a sample of attachments
    sample_entries = Entry.joins(:poster_attachment).limit(10)

    puts "\n🧪 Testing sample attachments..."
    sample_entries.each do |entry|
      begin
        if entry.poster.attached? && entry.poster.url.present?
          puts "   ✅ #{entry.name} - Attachment OK"
        else
          puts "   ❌ #{entry.name} - Attachment broken"
          broken_attachments += 1
        end
      rescue StandardError => e
        puts "   💥 #{entry.name} - Error: #{e.message}"
        broken_attachments += 1
      end
    end

    if broken_attachments == 0
      puts "\n✅ All tested attachments are working properly!"
    else
      puts "\n⚠️  Found #{broken_attachments} broken attachments in sample"
      puts "💡 You may need to check Cloudinary configuration or asset accessibility"
    end

    # Check Cloudinary configuration
    puts "\n⚙️  Cloudinary Configuration:"
    puts "   Service: #{Rails.application.config.active_storage.service}"
    puts "   Cloud Name: #{ENV['CLOUDINARY_CLOUD_NAME'] ? '✅ Set' : '❌ Missing'}"
    puts "   API Key: #{ENV['CLOUDINARY_API_KEY'] ? '✅ Set' : '❌ Missing'}"
    puts "   API Secret: #{ENV['CLOUDINARY_API_SECRET'] ? '✅ Set' : '❌ Missing'}"
  end

  desc "Update Cloudinary folder configuration for shared assets"
  task update_cloudinary_config: :environment do
    storage_file = Rails.root.join('config', 'storage.yml')

    puts "🔧 Updating Cloudinary configuration for shared assets..."
    puts "📁 File: #{storage_file}"

    # Read current configuration
    config = YAML.load_file(storage_file)

    # Update cloudinary configuration
    if config['cloudinary']
      old_folder = config['cloudinary']['folder']
      config['cloudinary']['folder'] = 'shared'

      # Write back to file
      File.write(storage_file, YAML.dump(config))

      puts "✅ Updated Cloudinary folder configuration:"
      puts "   From: #{old_folder}"
      puts "   To: shared"
      puts ""
      puts "🔄 This change allows both development and production to use the same Cloudinary assets"
      puts "⚠️  Restart your Rails server for changes to take effect"
    else
      puts "❌ No cloudinary configuration found in storage.yml"
    end
  end

  desc "Show export/import help"
  task :help do
    puts <<~HELP
      📦 Data Export/Import Tasks for Production Deployment

      Available commands:

      📋 Export development data for production:
         rails data:export_for_production

      🔍 Verify import integrity:
         rails data:verify_import

      🔧 Update Cloudinary config for shared assets:
         rails data:update_cloudinary_config

      ❓ Show this help:
         rails data:help

      ## Deployment Workflow:

      1. **In Development:**
         ```bash
         rails data:export_for_production
         rails data:update_cloudinary_config  # Optional: for shared folder
         ```

      2. **Deploy to Production:**
         - Copy export files to production server
         - Import database dump
         - Set same Cloudinary credentials
         - Verify with rails data:verify_import

      3. **Benefits:**
         - Zero duplicate Cloudinary uploads
         - Preserves all Active Storage attachments
         - Maintains image optimizations
         - Seamless production deployment

      See generated IMPORT_INSTRUCTIONS.md for detailed steps!
    HELP
  end
end
