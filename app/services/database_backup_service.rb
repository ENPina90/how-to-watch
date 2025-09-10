require 'json'
require 'fileutils'
require 'zip'

class DatabaseBackupService
  BACKUP_VERSION = "1.0"

  def initialize(backup_dir = nil)
    @backup_dir = backup_dir || Rails.root.join('db', 'backups')
    ensure_backup_directory
  end

  def create_full_backup(include_attachments: true)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    backup_name = "full_backup_#{timestamp}"
    backup_path = @backup_dir.join(backup_name)

    Rails.logger.info "Creating full backup: #{backup_name}"

    FileUtils.mkdir_p(backup_path)

    # Create backup manifest
    manifest = {
      version: BACKUP_VERSION,
      type: 'full',
      timestamp: timestamp,
      created_at: Time.current.iso8601,
      rails_env: Rails.env,
      database_adapter: ActiveRecord::Base.connection.adapter_name,
      include_attachments: include_attachments
    }

    # Export all tables
    tables_data = export_all_tables

    # Export Active Storage attachments if requested
    attachments_data = include_attachments ? export_attachments : nil

    # Write data files
    File.write(backup_path.join('manifest.json'), JSON.pretty_generate(manifest))
    File.write(backup_path.join('tables.json'), JSON.pretty_generate(tables_data))
    File.write(backup_path.join('attachments.json'), JSON.pretty_generate(attachments_data)) if attachments_data

    # Create compressed archive
    zip_path = create_zip_archive(backup_path, backup_name)

    # Clean up temporary directory
    FileUtils.rm_rf(backup_path)

    Rails.logger.info "Full backup completed: #{zip_path}"

    {
      success: true,
      backup_file: zip_path,
      manifest: manifest,
      stats: calculate_backup_stats(tables_data, attachments_data)
    }
  rescue StandardError => e
    Rails.logger.error "Backup failed: #{e.message}"
    FileUtils.rm_rf(backup_path) if backup_path&.exist?
    { success: false, error: e.message }
  end

  def create_incremental_backup(since: nil, include_attachments: true)
    since ||= last_backup_timestamp

    if since.nil?
      Rails.logger.info "No previous backup found, creating full backup instead"
      return create_full_backup(include_attachments: include_attachments)
    end

    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    backup_name = "incremental_backup_#{timestamp}"
    backup_path = @backup_dir.join(backup_name)

    Rails.logger.info "Creating incremental backup since #{since}"

    FileUtils.mkdir_p(backup_path)

    # Create backup manifest
    manifest = {
      version: BACKUP_VERSION,
      type: 'incremental',
      timestamp: timestamp,
      created_at: Time.current.iso8601,
      since: since.iso8601,
      rails_env: Rails.env,
      database_adapter: ActiveRecord::Base.connection.adapter_name,
      include_attachments: include_attachments
    }

    # Export changed records
    tables_data = export_changed_tables(since)

    # Export new attachments
    attachments_data = include_attachments ? export_changed_attachments(since) : nil

    # Write data files
    File.write(backup_path.join('manifest.json'), JSON.pretty_generate(manifest))
    File.write(backup_path.join('tables.json'), JSON.pretty_generate(tables_data))
    File.write(backup_path.join('attachments.json'), JSON.pretty_generate(attachments_data)) if attachments_data

    # Create compressed archive
    zip_path = create_zip_archive(backup_path, backup_name)

    # Clean up temporary directory
    FileUtils.rm_rf(backup_path)

    Rails.logger.info "Incremental backup completed: #{zip_path}"

    {
      success: true,
      backup_file: zip_path,
      manifest: manifest,
      stats: calculate_backup_stats(tables_data, attachments_data)
    }
  rescue StandardError => e
    Rails.logger.error "Incremental backup failed: #{e.message}"
    FileUtils.rm_rf(backup_path) if backup_path&.exist?
    { success: false, error: e.message }
  end

  def restore_backup(backup_file, options = {})
    restore_attachments = options.fetch(:restore_attachments, true)
    clean_before_restore = options.fetch(:clean_before_restore, false)

    Rails.logger.info "Restoring backup from: #{backup_file}"

    # Extract backup
    temp_dir = extract_backup(backup_file)
    manifest = load_manifest(temp_dir)

    # Validate backup
    validate_backup_compatibility(manifest)

    # Clean database if requested
    clean_database if clean_before_restore

    # Restore tables
    restore_tables(temp_dir, manifest)

    # Restore attachments
    restore_attachments(temp_dir, manifest) if restore_attachments && manifest['include_attachments']

    # Clean up
    FileUtils.rm_rf(temp_dir)

    Rails.logger.info "Backup restoration completed successfully"

    { success: true, manifest: manifest }
  rescue StandardError => e
    Rails.logger.error "Backup restoration failed: #{e.message}"
    FileUtils.rm_rf(temp_dir) if temp_dir&.exist?
    { success: false, error: e.message }
  end

  def list_backups
    return [] unless @backup_dir.exist?

    backup_files = Dir.glob(@backup_dir.join('*.zip')).sort.reverse

    backup_files.map do |file|
      begin
        temp_dir = extract_backup(file)
        manifest = load_manifest(temp_dir)
        FileUtils.rm_rf(temp_dir)

        {
          file: file,
          name: File.basename(file, '.zip'),
          type: manifest['type'],
          created_at: Time.parse(manifest['created_at']),
          size: File.size(file),
          rails_env: manifest['rails_env']
        }
      rescue StandardError => e
        Rails.logger.warn "Could not read backup manifest for #{file}: #{e.message}"
        {
          file: file,
          name: File.basename(file, '.zip'),
          type: 'unknown',
          created_at: File.mtime(file),
          size: File.size(file),
          error: e.message
        }
      end
    end
  end

  private

  def ensure_backup_directory
    FileUtils.mkdir_p(@backup_dir) unless @backup_dir.exist?
  end

  def export_all_tables
    tables = {}

    # Get all model classes
    model_classes = get_model_classes

    model_classes.each do |model_class|
      table_name = model_class.table_name
      Rails.logger.info "Exporting table: #{table_name}"

      records = model_class.all.map do |record|
        attributes = record.attributes

        # Include attachment information
        if record.respond_to?(:attachment_reflections)
          record.attachment_reflections.each do |name, reflection|
            attachment = record.send(name)
            if attachment.attached?
              attributes["#{name}_attachment"] = {
                filename: attachment.filename.to_s,
                content_type: attachment.content_type,
                byte_size: attachment.byte_size,
                checksum: attachment.checksum,
                service_name: attachment.service_name,
                key: attachment.key
              }
            end
          end
        end

        attributes
      end

      tables[table_name] = {
        model_class: model_class.name,
        count: records.size,
        records: records
      }
    end

    tables
  end

  def export_changed_tables(since)
    tables = {}

    model_classes = get_model_classes

    model_classes.each do |model_class|
      table_name = model_class.table_name

      # Skip tables without timestamps
      next unless model_class.column_names.include?('updated_at')

      changed_records = model_class.where('updated_at > ?', since).map do |record|
        attributes = record.attributes

        # Include attachment information for changed records
        if record.respond_to?(:attachment_reflections)
          record.attachment_reflections.each do |name, reflection|
            attachment = record.send(name)
            if attachment.attached?
              attributes["#{name}_attachment"] = {
                filename: attachment.filename.to_s,
                content_type: attachment.content_type,
                byte_size: attachment.byte_size,
                checksum: attachment.checksum,
                service_name: attachment.service_name,
                key: attachment.key
              }
            end
          end
        end

        attributes
      end

      if changed_records.any?
        Rails.logger.info "Exporting #{changed_records.size} changed records from #{table_name}"
        tables[table_name] = {
          model_class: model_class.name,
          count: changed_records.size,
          records: changed_records
        }
      end
    end

    tables
  end

  def export_attachments
    attachments = []

    ActiveStorage::Attachment.includes(:blob).find_each do |attachment|
      blob = attachment.blob

      attachments << {
        id: attachment.id,
        name: attachment.name,
        record_type: attachment.record_type,
        record_id: attachment.record_id,
        blob_id: attachment.blob_id,
        created_at: attachment.created_at,
        blob_data: {
          id: blob.id,
          key: blob.key,
          filename: blob.filename,
          content_type: blob.content_type,
          metadata: blob.metadata,
          service_name: blob.service_name,
          byte_size: blob.byte_size,
          checksum: blob.checksum,
          created_at: blob.created_at
        }
      }
    end

    { count: attachments.size, attachments: attachments }
  end

  def export_changed_attachments(since)
    attachments = []

    ActiveStorage::Attachment.includes(:blob)
                            .where('active_storage_attachments.created_at > ?', since)
                            .find_each do |attachment|
      blob = attachment.blob

      attachments << {
        id: attachment.id,
        name: attachment.name,
        record_type: attachment.record_type,
        record_id: attachment.record_id,
        blob_id: attachment.blob_id,
        created_at: attachment.created_at,
        blob_data: {
          id: blob.id,
          key: blob.key,
          filename: blob.filename,
          content_type: blob.content_type,
          metadata: blob.metadata,
          service_name: blob.service_name,
          byte_size: blob.byte_size,
          checksum: blob.checksum,
          created_at: blob.created_at
        }
      }
    end

    { count: attachments.size, attachments: attachments }
  end

  def restore_tables(backup_dir, manifest)
    tables_file = backup_dir.join('tables.json')
    return unless tables_file.exist?

    tables_data = JSON.parse(File.read(tables_file))

    # Restore in dependency order
    restoration_order = determine_restoration_order(tables_data.keys)

    ActiveRecord::Base.transaction do
      restoration_order.each do |table_name|
        table_data = tables_data[table_name]
        next unless table_data

        model_class = table_data['model_class'].constantize
        records = table_data['records']

        Rails.logger.info "Restoring #{records.size} records to #{table_name}"

        records.each do |record_data|
          # Separate attachment data
          attachment_data = {}
          clean_attributes = record_data.except(*record_data.keys.select { |k| k.end_with?('_attachment') })

          record_data.each do |key, value|
            if key.end_with?('_attachment')
              attachment_name = key.gsub('_attachment', '')
              attachment_data[attachment_name] = value
            end
          end

          # Create or update record
          record = model_class.find_by(id: clean_attributes['id'])
          if record
            record.update!(clean_attributes.except('id'))
          else
            record = model_class.create!(clean_attributes)
          end

          # Restore attachments
          attachment_data.each do |attachment_name, attachment_info|
            restore_record_attachment(record, attachment_name, attachment_info)
          end
        end
      end
    end
  end

  def restore_attachments(backup_dir, manifest)
    attachments_file = backup_dir.join('attachments.json')
    return unless attachments_file.exist?

    attachments_data = JSON.parse(File.read(attachments_file))
    attachments = attachments_data['attachments']

    Rails.logger.info "Restoring #{attachments.size} Active Storage attachments"

    attachments.each do |attachment_data|
      restore_attachment(attachment_data)
    end
  end

  def restore_attachment(attachment_data)
    blob_data = attachment_data['blob_data']

    # Create or find blob
    blob = ActiveStorage::Blob.find_by(key: blob_data['key'])
    unless blob
      blob = ActiveStorage::Blob.create!(
        key: blob_data['key'],
        filename: blob_data['filename'],
        content_type: blob_data['content_type'],
        metadata: blob_data['metadata'],
        service_name: blob_data['service_name'],
        byte_size: blob_data['byte_size'],
        checksum: blob_data['checksum']
      )
    end

    # Create attachment if it doesn't exist
    attachment = ActiveStorage::Attachment.find_by(
      name: attachment_data['name'],
      record_type: attachment_data['record_type'],
      record_id: attachment_data['record_id'],
      blob_id: blob.id
    )

    unless attachment
      ActiveStorage::Attachment.create!(
        name: attachment_data['name'],
        record_type: attachment_data['record_type'],
        record_id: attachment_data['record_id'],
        blob_id: blob.id
      )
    end
  end

  def restore_record_attachment(record, attachment_name, attachment_info)
    return unless record.respond_to?(attachment_name)
    return if record.send(attachment_name).attached?

    # Find or create blob
    blob = ActiveStorage::Blob.find_by(key: attachment_info['key'])
    unless blob
      blob = ActiveStorage::Blob.create!(
        key: attachment_info['key'],
        filename: attachment_info['filename'],
        content_type: attachment_info['content_type'],
        metadata: {},
        service_name: attachment_info['service_name'],
        byte_size: attachment_info['byte_size'],
        checksum: attachment_info['checksum']
      )
    end

    # Attach blob to record
    record.send(attachment_name).attach(blob)
  end

  def create_zip_archive(source_path, backup_name)
    zip_path = @backup_dir.join("#{backup_name}.zip")

    Zip::File.open(zip_path, Zip::File::CREATE) do |zipfile|
      Dir.glob(source_path.join('*')).each do |file|
        zipfile.add(File.basename(file), file)
      end
    end

    zip_path
  end

  def extract_backup(backup_file)
    temp_dir = Rails.root.join('tmp', 'backup_restore', SecureRandom.hex(8))
    FileUtils.mkdir_p(temp_dir)

    Zip::File.open(backup_file) do |zip_file|
      zip_file.each do |entry|
        entry.extract(temp_dir.join(entry.name))
      end
    end

    temp_dir
  end

  def load_manifest(backup_dir)
    manifest_file = backup_dir.join('manifest.json')
    raise "Backup manifest not found" unless manifest_file.exist?

    JSON.parse(File.read(manifest_file))
  end

  def validate_backup_compatibility(manifest)
    if manifest['version'] != BACKUP_VERSION
      Rails.logger.warn "Backup version mismatch: #{manifest['version']} vs #{BACKUP_VERSION}"
    end

    if manifest['database_adapter'] != ActiveRecord::Base.connection.adapter_name
      Rails.logger.warn "Database adapter mismatch: #{manifest['database_adapter']} vs #{ActiveRecord::Base.connection.adapter_name}"
    end
  end

  def clean_database
    Rails.logger.info "Cleaning database before restore"

    # Disable foreign key checks temporarily
    ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 0") if ActiveRecord::Base.connection.adapter_name == 'Mysql2'

    get_model_classes.each do |model_class|
      model_class.delete_all
    end

    # Clean Active Storage
    ActiveStorage::Attachment.delete_all
    ActiveStorage::Blob.delete_all

    # Re-enable foreign key checks
    ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 1") if ActiveRecord::Base.connection.adapter_name == 'Mysql2'
  end

  def get_model_classes
    # Get all model classes that inherit from ApplicationRecord
    Rails.application.eager_load!

    ApplicationRecord.descendants.reject do |model|
      model.abstract_class? ||
      model.table_name.start_with?('active_storage_') ||
      !model.table_exists?
    end.sort_by(&:table_name)
  end

  def determine_restoration_order(table_names)
    # Simple dependency resolution - put users and lists first, then everything else
    priority_tables = %w[users lists]

    ordered_tables = []
    ordered_tables += priority_tables.select { |table| table_names.include?(table) }
    ordered_tables += (table_names - priority_tables)

    ordered_tables
  end

  def calculate_backup_stats(tables_data, attachments_data)
    stats = {
      total_records: tables_data.values.sum { |table| table['count'] || 0 },
      tables_count: tables_data.keys.size,
      table_breakdown: tables_data.transform_values { |table| table['count'] || 0 }
    }

    if attachments_data
      stats[:total_attachments] = attachments_data['count'] || 0
    end

    stats
  end

  def last_backup_timestamp
    backups = list_backups
    return nil if backups.empty?

    backups.first[:created_at]
  end
end
