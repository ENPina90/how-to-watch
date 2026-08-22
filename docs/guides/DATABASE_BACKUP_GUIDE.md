# Database Backup & Sync System

This guide explains how to use the new comprehensive database backup and synchronization system that replaces the old CSV-based approach.

## Overview

The new backup system provides:
- **Complete Data Export**: All database tables, relationships, and metadata
- **Active Storage Integration**: Cloudinary attachments are preserved
- **Incremental Backups**: Only backup changes since last backup
- **Cross-Environment Sync**: Easy sharing between development machines
- **Automated Operations**: Simple rake tasks for all operations

## Quick Start

### Create Your First Backup
```bash
# Full backup with attachments (recommended)
rake db:backup:full

# Full backup without attachments (faster)
rake db:backup:full[false]
```

### List Available Backups
```bash
rake db:backup:list
```

### Restore a Backup
```bash
# Restore specific backup (preserves existing data)
rake db:backup:restore[backup_filename.zip]

# Restore and clean database first (replaces all data)
rake db:backup:restore[backup_filename.zip,true,true]
```

## Detailed Usage

### Creating Backups

#### Full Backup
Creates a complete backup of your entire database:
```bash
# With Active Storage attachments (recommended for complete sync)
rake db:backup:full

# Without attachments (faster, smaller file)
rake db:backup:full[false]
```

#### Incremental Backup
Creates a backup of only changes since the last backup:
```bash
# Incremental with attachments
rake db:backup:incremental

# Incremental without attachments
rake db:backup:incremental[false]
```

### Restoring Backups

#### Basic Restore
Restores data while preserving existing records:
```bash
rake db:backup:restore[backup_filename.zip]
```

#### Clean Restore
**⚠️ WARNING: This deletes all existing data!**
```bash
rake db:backup:restore[backup_filename.zip,true,true]
```

#### Restore Options
- `backup_filename.zip`: The backup file to restore
- `restore_attachments` (default: true): Whether to restore Active Storage attachments
- `clean_before_restore` (default: false): Whether to delete all data before restoring

### Managing Backups

#### List All Backups
```bash
rake db:backup:list
```

#### Clean Old Backups
```bash
# Keep last 10 backups (default)
rake db:backup:clean

# Keep last 5 backups
rake db:backup:clean[5]
```

## Cross-Machine Database Sync

### Scenario 1: Sync to Another Development Machine

1. **On source machine** (create backup):
   ```bash
   rake db:backup:sync
   ```

2. **Transfer the backup file** using one of these methods:
   - **SCP/SSH**: `scp db/backups/backup_file.zip user@target-machine:~/`
   - **Cloud Storage**: Upload to Dropbox, Google Drive, etc.
   - **USB Drive**: Copy the backup file
   - **Git LFS**: For team sharing (add backup files to Git LFS)

3. **On target machine** (restore backup):
   ```bash
   # Place backup in db/backups/ directory
   mkdir -p db/backups
   mv ~/backup_file.zip db/backups/

   # Restore (this replaces ALL data)
   rake db:backup:restore[backup_file.zip,true,true]
   ```

### Scenario 2: Quick Development Setup

For setting up a new development environment:

```bash
# 1. Clone the repository
git clone <repository-url>
cd <project-directory>

# 2. Install dependencies
bundle install

# 3. Setup database
rails db:create db:migrate

# 4. Get backup file from team member and place in db/backups/

# 5. Restore backup
rake db:backup:restore[team_backup.zip,true,true]

# 6. Verify
rails console
# Check: User.count, Entry.count, etc.
```

## What Gets Backed Up

### Database Tables
- ✅ **users**: All user accounts and settings
- ✅ **lists**: All movie/TV lists
- ✅ **entries**: All movies and TV shows
- ✅ **subentries**: Episode data
- ✅ **user_entries**: User completion tracking
- ✅ **follows**: List following relationships
- ✅ **subscriptions**: List subscriptions
- ✅ **list_relationships**: Parent/child list relationships
- ✅ **list_user_entries**: User list progress
- ✅ **failed_entries**: Import failure tracking

### Active Storage (Cloudinary)
- ✅ **Poster Images**: All movie/TV show posters
- ✅ **Attachment Metadata**: File names, sizes, checksums
- ✅ **Cloudinary References**: Service keys and URLs

### What's NOT Backed Up
- ❌ **Rails logs**: Not included in backups
- ❌ **Temporary files**: Cache and tmp directories
- ❌ **Environment variables**: Database credentials, API keys
- ❌ **Application code**: Only data is backed up

## File Structure

Backups are stored in:
```
db/backups/
├── full_backup_20250909_215457.zip
├── incremental_backup_20250909_220130.zip
└── ...
```

Each backup contains:
```
backup.zip
├── manifest.json          # Backup metadata
├── tables.json            # All database records
└── attachments.json       # Active Storage data (if included)
```

## Advanced Usage

### Environment Compatibility Check
```bash
rails runner "DatabaseMigrationHelper.validate_environment_compatibility"
```

### Development Export Helper
```ruby
# In Rails console
DatabaseMigrationHelper.export_for_development
```

### Production Backup Preparation
```ruby
# In Rails console
DatabaseMigrationHelper.prepare_for_production
```

## Troubleshooting

### Common Issues

#### "Backup file not found"
```bash
# Check available backups
rake db:backup:list

# Ensure backup file is in db/backups/ directory
ls -la db/backups/
```

#### "Database connection error"
```bash
# Check database is running
rails db:migrate:status

# Verify environment setup
rails runner "DatabaseMigrationHelper.validate_environment_compatibility"
```

#### "Cloudinary attachments not restoring"
```bash
# Verify CLOUDINARY_URL is set
echo $CLOUDINARY_URL

# Check Active Storage configuration
rails runner "puts ActiveStorage::Blob.count"
```

### Performance Tips

1. **Use incremental backups** for regular backups
2. **Exclude attachments** if only syncing database structure
3. **Clean old backups** regularly to save disk space
4. **Compress large backups** before transferring

## Migration from CSV System

### Old CSV System
```bash
# OLD: Limited export
rake export:entries

# OLD: Manual CSV import
# Complex manual process
```

### New Backup System
```bash
# NEW: Complete backup
rake db:backup:full

# NEW: Simple restore
rake db:backup:restore[backup.zip,true,true]
```

### Benefits of New System
- ✅ **Complete data preservation**: All relationships and metadata
- ✅ **Active Storage support**: Poster images included
- ✅ **Automated process**: No manual CSV handling
- ✅ **Version control**: Multiple backup versions
- ✅ **Cross-platform**: Works on any machine with same Rails setup

## Best Practices

1. **Regular Backups**: Create backups before major changes
2. **Test Restores**: Verify backups work by testing restore process
3. **Secure Storage**: Keep backups in secure, backed-up locations
4. **Document Changes**: Note what changed between backups
5. **Environment Separation**: Use different backup strategies for development vs production

## Convenience Aliases

These shorter commands are also available:
```bash
# Aliases for common operations
rake backup:create      # Same as db:backup:full
rake backup:restore[file.zip]  # Same as db:backup:restore
rake backup:list        # Same as db:backup:list
```

---

## Support

If you encounter issues:
1. Check the Rails logs for detailed error messages
2. Verify environment compatibility with the validation command
3. Ensure all dependencies are installed (`bundle install`)
4. Check database connectivity and permissions

For development questions, refer to the backup service source code in:
- `app/services/database_backup_service.rb`
- `app/services/database_migration_helper.rb`
- `lib/tasks/database_backup.rake`
