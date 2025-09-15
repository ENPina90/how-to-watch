namespace :db do
  namespace :backup do
    desc "Create a full database backup with Active Storage attachments"
    task :full, [:include_attachments] => :environment do |t, args|
      include_attachments = args[:include_attachments] != 'false'

      puts "Creating full database backup..."
      puts "Include attachments: #{include_attachments ? 'yes' : 'no'}"

      service = DatabaseBackupService.new
      result = service.create_full_backup(include_attachments: include_attachments)

      if result[:success]
        puts "✅ Backup completed successfully!"
        puts "📁 Backup file: #{result[:backup_file]}"
        puts "📊 Stats:"
        puts "   - Tables: #{result[:stats][:tables_count]}"
        puts "   - Total records: #{result[:stats][:total_records]}"
        puts "   - Attachments: #{result[:stats][:total_attachments] || 'N/A'}" if include_attachments
        puts ""
        puts "🔄 To restore this backup on another machine:"
        puts "   rake db:backup:restore[#{File.basename(result[:backup_file])}]"
      else
        puts "❌ Backup failed: #{result[:error]}"
        exit 1
      end
    end

    desc "Create an incremental database backup (only changes since last backup)"
    task :incremental, [:include_attachments] => :environment do |t, args|
      include_attachments = args[:include_attachments] != 'false'

      puts "Creating incremental database backup..."
      puts "Include attachments: #{include_attachments ? 'yes' : 'no'}"

      service = DatabaseBackupService.new
      result = service.create_incremental_backup(include_attachments: include_attachments)

      if result[:success]
        puts "✅ Incremental backup completed successfully!"
        puts "📁 Backup file: #{result[:backup_file]}"
        puts "📊 Stats:"
        puts "   - Tables: #{result[:stats][:tables_count]}"
        puts "   - Total records: #{result[:stats][:total_records]}"
        puts "   - Attachments: #{result[:stats][:total_attachments] || 'N/A'}" if include_attachments

        if result[:manifest][:type] == 'full'
          puts "ℹ️  No previous backup found - created full backup instead"
        else
          puts "📅 Changes since: #{result[:manifest][:since]}"
        end

        puts ""
        puts "🔄 To restore this backup on another machine:"
        puts "   rake db:backup:restore[#{File.basename(result[:backup_file])}]"
      else
        puts "❌ Incremental backup failed: #{result[:error]}"
        exit 1
      end
    end

    desc "Restore database from backup file"
    task :restore, [:backup_file, :restore_attachments, :clean_before_restore] => :environment do |t, args|
      backup_file = args[:backup_file]
      restore_attachments = args[:restore_attachments] != 'false'
      clean_before_restore = args[:clean_before_restore] == 'true'

      unless backup_file
        puts "❌ Please specify a backup file:"
        puts "   rake db:backup:restore[backup_filename.zip]"
        exit 1
      end

      # Find backup file
      backup_service = DatabaseBackupService.new
      backup_dir = Rails.root.join('db', 'backups')
      backup_path = backup_dir.join(backup_file)

      unless backup_path.exist?
        puts "❌ Backup file not found: #{backup_path}"
        puts ""
        puts "Available backups:"
        backup_service.list_backups.each do |backup|
          puts "   - #{File.basename(backup[:file])}"
        end
        exit 1
      end

      puts "🔄 Restoring database from backup..."
      puts "📁 Backup file: #{backup_path}"
      puts "🖼️  Restore attachments: #{restore_attachments ? 'yes' : 'no'}"
      puts "🧹 Clean before restore: #{clean_before_restore ? 'yes' : 'no'}"

      if clean_before_restore
        puts ""
        puts "⚠️  WARNING: This will DELETE ALL existing data!"
        print "Are you sure you want to continue? (yes/no): "
        confirmation = STDIN.gets.chomp.downcase

        unless confirmation == 'yes'
          puts "Restoration cancelled."
          exit 0
        end
      end

      result = backup_service.restore_backup(backup_path, {
        restore_attachments: restore_attachments,
        clean_before_restore: clean_before_restore
      })

      if result[:success]
        puts "✅ Database restoration completed successfully!"
        puts "📊 Restored from backup created: #{result[:manifest]['created_at']}"
        puts "🏷️  Backup type: #{result[:manifest]['type']}"
        puts "🌍 Original environment: #{result[:manifest]['rails_env']}"
      else
        puts "❌ Database restoration failed: #{result[:error]}"
        exit 1
      end
    end

    desc "List all available backups"
    task :list => :environment do
      service = DatabaseBackupService.new
      backups = service.list_backups

      if backups.empty?
        puts "No backups found."
        puts ""
        puts "Create your first backup with:"
        puts "   rake db:backup:full"
        exit 0
      end

      puts "Available backups:"
      puts ""

      backups.each do |backup|
        status_icon = backup[:error] ? '❌' : '✅'
        size_mb = (backup[:size] / 1024.0 / 1024.0).round(2)

        puts "#{status_icon} #{backup[:name]}"
        puts "   📅 Created: #{backup[:created_at].strftime('%Y-%m-%d %H:%M:%S')}"
        puts "   🏷️  Type: #{backup[:type]}"
        puts "   📦 Size: #{size_mb} MB"
        puts "   🌍 Environment: #{backup[:rails_env]}"
        puts "   📁 File: #{File.basename(backup[:file])}"

        if backup[:error]
          puts "   ❌ Error: #{backup[:error]}"
        end

        puts ""
      end

      puts "To restore a backup:"
      puts "   rake db:backup:restore[backup_filename.zip]"
    end

    desc "Clean old backups (keep last N backups)"
    task :clean, [:keep_count] => :environment do |t, args|
      keep_count = (args[:keep_count] || '10').to_i

      service = DatabaseBackupService.new
      backups = service.list_backups

      if backups.size <= keep_count
        puts "Only #{backups.size} backups found, nothing to clean (keeping #{keep_count})"
        exit 0
      end

      to_delete = backups[keep_count..-1]

      puts "Found #{backups.size} backups, keeping #{keep_count}, deleting #{to_delete.size}:"
      puts ""

      to_delete.each do |backup|
        puts "🗑️  #{backup[:name]} (#{backup[:created_at].strftime('%Y-%m-%d %H:%M:%S')})"
      end

      puts ""
      print "Are you sure you want to delete these #{to_delete.size} backups? (yes/no): "
      confirmation = STDIN.gets.chomp.downcase

      unless confirmation == 'yes'
        puts "Cleanup cancelled."
        exit 0
      end

      deleted_count = 0
      to_delete.each do |backup|
        begin
          File.delete(backup[:file])
          deleted_count += 1
          puts "✅ Deleted: #{backup[:name]}"
        rescue StandardError => e
          puts "❌ Failed to delete #{backup[:name]}: #{e.message}"
        end
      end

      puts ""
      puts "🧹 Cleanup completed: #{deleted_count} backups deleted"
    end

    desc "Sync database to another machine (create backup and show transfer instructions)"
    task :sync => :environment do
      puts "🔄 Creating backup for database sync..."

      service = DatabaseBackupService.new
      result = service.create_full_backup(include_attachments: true)

      if result[:success]
        backup_file = File.basename(result[:backup_file])

        puts "✅ Backup created successfully!"
        puts ""
        puts "📋 To sync this database to another machine:"
        puts ""
        puts "1. Copy the backup file to the target machine:"
        puts "   scp #{result[:backup_file]} user@target-machine:~/backup.zip"
        puts ""
        puts "2. On the target machine, place the backup in db/backups/:"
        puts "   mkdir -p db/backups"
        puts "   mv ~/backup.zip db/backups/#{backup_file}"
        puts ""
        puts "3. Restore the backup:"
        puts "   rake db:backup:restore[#{backup_file},true,true]"
        puts ""
        puts "💡 Alternative: Use cloud storage (Dropbox, Google Drive, etc.)"
        puts "   - Upload: #{result[:backup_file]}"
        puts "   - Download to target machine's db/backups/ directory"
        puts "   - Run restore command above"
      else
        puts "❌ Backup creation failed: #{result[:error]}"
        exit 1
      end
    end
  end
end

# Convenience aliases
namespace :backup do
  desc "Alias for db:backup:full"
  task :create => 'db:backup:full'

  desc "Alias for db:backup:restore"
  task :restore, [:backup_file] => 'db:backup:restore'

  desc "Alias for db:backup:list"
  task :list => 'db:backup:list'
end
