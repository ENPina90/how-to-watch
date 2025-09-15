puts "🧹 Clearing database (keeping admin users)..."

# Clear in dependency order
ActiveStorage::Attachment.destroy_all
puts "✅ Cleared Active Storage attachments"

ActiveStorage::Blob.destroy_all
puts "✅ Cleared Active Storage blobs"

# Clear your app data
Subentry.destroy_all
puts "✅ Cleared subentries"

Entry.destroy_all
puts "✅ Cleared entries"

List.destroy_all
puts "✅ Cleared lists"

# Clear users EXCEPT admin/important ones (adjust email as needed)
User.where.not(email: ['admin@example.com', 'your-email@example.com']).destroy_all
puts "✅ Cleared users (kept admin accounts)"

puts "Database cleared! Starting fresh import..."
puts "Current counts: Users: #{User.count}, Lists: #{List.count}, Entries: #{Entry.count}"

# Now import fresh data
tables_data = JSON.parse(File.read('/tmp/tables.json'))

# 1. Import users
if tables_data['users']
  puts "👥 Importing #{tables_data['users']['count']} users..."
  tables_data['users']['records'].each do |user_data|
    user = User.find_or_initialize_by(id: user_data['id'])
    user.assign_attributes(user_data.except('id', 'encrypted_password'))
    user.password = '123456' if user.new_record?
    user.password_confirmation = '123456' if user.new_record?
    user.save!(validate: false)
    print "."
  end
  puts "\n✅ Users imported: #{User.count}"
end

# 2. Import lists
if tables_data['lists']
  puts "📋 Importing #{tables_data['lists']['count']} lists..."
  tables_data['lists']['records'].each do |list_data|
    list = List.find_or_initialize_by(id: list_data['id'])
    list.assign_attributes(list_data.except('id'))
    list.save!
    print "."
  end
  puts "\n✅ Lists imported: #{List.count}"
end

# 3. Import entries (without current_id first)
if tables_data['entries']
  puts "🎬 Importing #{tables_data['entries']['count']} entries..."
  success_count = 0

  tables_data['entries']['records'].each_with_index do |entry_data, index|
    begin
      entry = Entry.new(entry_data.except('id', 'current_id', 'poster_attachment', 'poster'))
      entry.id = entry_data['id']
      entry.save!
      success_count += 1

      if (index + 1) % 100 == 0
        puts "Imported #{success_count}/#{index + 1} entries..."
      end
    rescue => e
      puts "Error importing entry #{entry_data['id']}: #{e.message}" if success_count < 10
    end
  end
  puts "✅ Entries imported: #{Entry.count}"
end

# 4. Import subentries
if tables_data['subentries']
  puts "📺 Importing #{tables_data['subentries']['count']} subentries..."
  tables_data['subentries']['records'].each do |subentry_data|
    begin
      subentry = Subentry.new(subentry_data.except('id'))
      subentry.id = subentry_data['id']
      subentry.save!
      print "."
    rescue => e
      # Skip errors
    end
  end
  puts "\n✅ Subentries imported: #{Subentry.count}"
end

# 5. Update entries with current_id
if tables_data['entries']
  puts "🔗 Updating entries with current_id references..."
  updated_count = 0

  tables_data['entries']['records'].each do |entry_data|
    if entry_data['current_id']
      begin
        entry = Entry.find(entry_data['id'])
        entry.update_column(:current_id, entry_data['current_id'])
        updated_count += 1
      rescue => e
        # Skip if entry or subentry doesn't exist
      end
    end
  end
  puts "✅ Updated #{updated_count} entries with current_id"
end

puts "🎉 Clean import completed!"
puts "Final counts:"
puts "- Users: #{User.count}"
puts "- Lists: #{List.count}"
puts "- Entries: #{Entry.count}"
puts "- Subentries: #{Subentry.count}"
