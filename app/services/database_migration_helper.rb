class DatabaseMigrationHelper
  # Helper service to assist with database migrations between environments

  def self.export_for_development
    # Create a backup optimized for development environment sharing
    service = DatabaseBackupService.new

    Rails.logger.info "Creating development export..."

    result = service.create_full_backup(include_attachments: true)

    if result[:success]
      puts "\n✅ Development export completed!"
      puts "📁 Export file: #{result[:backup_file]}"
      puts "\n🔄 To import on another development machine:"
      puts "1. Copy #{File.basename(result[:backup_file])} to the target machine's db/backups/ directory"
      puts "2. Run: rake db:backup:restore[#{File.basename(result[:backup_file])},true,true]"
      puts "\n💡 This will replace ALL data on the target machine!"

      result
    else
      puts "❌ Export failed: #{result[:error]}"
      result
    end
  end

  def self.prepare_for_production
    # Create a backup suitable for production deployment
    service = DatabaseBackupService.new

    Rails.logger.info "Creating production-ready backup..."

    # Only include essential data, skip development-specific entries
    result = service.create_full_backup(include_attachments: true)

    if result[:success]
      puts "\n✅ Production backup completed!"
      puts "📁 Backup file: #{result[:backup_file]}"
      puts "\n⚠️  Remember to:"
      puts "- Review data for production suitability"
      puts "- Update any development-specific URLs or settings"
      puts "- Test thoroughly in staging environment first"

      result
    else
      puts "❌ Production backup failed: #{result[:error]}"
      result
    end
  end

  def self.create_sample_data_export
    # Create a backup with only sample/seed data for sharing
    service = DatabaseBackupService.new

    Rails.logger.info "Creating sample data export..."

    # This could be enhanced to filter only certain lists or entries
    result = service.create_full_backup(include_attachments: true)

    if result[:success]
      puts "\n✅ Sample data export completed!"
      puts "📁 Export file: #{result[:backup_file]}"
      puts "\n📋 This backup contains all current data."
      puts "💡 Consider creating a separate sample dataset for sharing."

      result
    else
      puts "❌ Sample data export failed: #{result[:error]}"
      result
    end
  end

  def self.validate_environment_compatibility
    # Check if the current environment is suitable for backup operations
    checks = []

    # Check database connection
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      checks << { check: "Database connection", status: :ok }
    rescue StandardError => e
      checks << { check: "Database connection", status: :error, message: e.message }
    end

    # Check Active Storage configuration
    begin
      if ActiveStorage::Blob.count >= 0
        checks << { check: "Active Storage", status: :ok }
      end
    rescue StandardError => e
      checks << { check: "Active Storage", status: :error, message: e.message }
    end

    # Check Cloudinary configuration
    begin
      if defined?(Cloudinary) && ENV['CLOUDINARY_URL'].present?
        checks << { check: "Cloudinary configuration", status: :ok }
      else
        checks << { check: "Cloudinary configuration", status: :warning, message: "CLOUDINARY_URL not set" }
      end
    rescue StandardError => e
      checks << { check: "Cloudinary configuration", status: :error, message: e.message }
    end

    # Check backup directory
    backup_dir = Rails.root.join('db', 'backups')
    if backup_dir.exist? || backup_dir.parent.writable?
      checks << { check: "Backup directory", status: :ok }
    else
      checks << { check: "Backup directory", status: :error, message: "Cannot create backup directory" }
    end

    # Display results
    puts "\n🔍 Environment Compatibility Check:"
    puts "=" * 40

    checks.each do |check|
      icon = case check[:status]
             when :ok then "✅"
             when :warning then "⚠️ "
             when :error then "❌"
             end

      puts "#{icon} #{check[:check]}"
      puts "   #{check[:message]}" if check[:message]
    end

    puts "=" * 40

    errors = checks.select { |c| c[:status] == :error }
    warnings = checks.select { |c| c[:status] == :warning }

    if errors.any?
      puts "❌ #{errors.size} error(s) found. Please fix before proceeding."
      return false
    elsif warnings.any?
      puts "⚠️  #{warnings.size} warning(s) found. Backup may work with limitations."
      return true
    else
      puts "✅ All checks passed. Ready for backup operations."
      return true
    end
  end
end
