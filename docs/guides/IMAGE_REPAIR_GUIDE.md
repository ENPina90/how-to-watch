# 🖼️ Image Repair Functionality Guide

This guide explains how to use the image validation and repair functionality that automatically fixes broken entry images using the TMDB API.

## 🎯 What It Does

- **Validates** entry image URLs to check if they're accessible
- **Repairs** broken images by fetching high-quality posters from TMDB
- **Batch processes** all entries or specific lists
- **Provides detailed reporting** on repair results

## 🚀 Quick Start

### Check for Broken Images
```bash
rails images:check
```
This will scan all entries and report which ones have broken image URLs.

### Repair All Broken Images
```bash
rails images:repair
```
This will automatically fix all broken images using TMDB posters.

### Repair Images for a Specific List
```bash
rails images:repair_list[123]
```
Replace `123` with your list ID.

## 📋 Available Commands

| Command | Description |
|---------|-------------|
| `rails images:check` | Scan and report broken images |
| `rails images:repair` | Fix all broken images |
| `rails images:repair_list[ID]` | Fix images for specific list |
| `rails images:test_url['URL']` | Test if a specific URL works |
| `rails images:help` | Show usage examples |

## 🔧 Programmatic Usage

### Check Individual Entry
```ruby
entry = Entry.find(123)

# Check if image is valid
if entry.image_valid?
  puts "Image is working!"
else
  puts "Image is broken"
end

# Repair the image
result = entry.repair_image!
puts result[:message]
```

### Use Services Directly
```ruby
# Initialize services
tmdb_service = TmdbService.new
repair_service = ImageRepairService.new

# Validate a URL
is_valid = tmdb_service.validate_image_url("https://example.com/image.jpg")

# Get TMDB poster
poster_url = tmdb_service.fetch_poster_url("550", "movie") # Fight Club

# Repair all images
results = repair_service.repair_all_images
puts "Repaired #{results[:repaired]} images"
```

## 🌐 Web Interface

You can also repair individual entry images through the web interface:

1. Go to any entry's detail page
2. Click the "Repair Image" button (if available)
3. The system will check and repair the image automatically

Route: `GET /entries/:id/repair_image`

## 🔍 How It Works

### Image Validation Process
1. **URL Check**: Verifies the URL is properly formatted
2. **HTTP Request**: Makes a HEAD request to check accessibility
3. **Content Type**: Confirms the response is an image
4. **Status Code**: Ensures the server returns 200 OK

### Image Repair Process
1. **Validation**: First checks if current image is broken
2. **TMDB Lookup**: Fetches poster from TMDB using the entry's `tmdb` field
3. **URL Replacement**: Updates the entry's `pic` field with new URL
4. **Quality**: Uses high-quality w500 size images from TMDB

## 📊 Understanding Results

### Status Types
- **✅ valid**: Image URL is working properly
- **🔧 repaired**: Successfully replaced with TMDB poster
- **⏭️ skipped**: Entry missing pic URL or TMDB ID
- **❌ failed**: Could not find replacement on TMDB
- **💥 error**: Technical error during processing

### Sample Output
```
📊 Repair Results:
   Total entries checked: 150
   ✅ Already valid: 120
   🔧 Successfully repaired: 25
   ⏭️ Skipped (no pic/tmdb): 3
   ❌ Failed to repair: 2
   💥 Errors: 0
```

## ⚙️ Configuration

### Required Environment Variables
```bash
TMDB_API_KEY=your_tmdb_api_key_here
```

### TMDB Image Sizes
The system uses `w500` size images (500px width) which provides:
- Good quality for most displays
- Reasonable file sizes
- Fast loading times

Available sizes: w92, w154, w185, w342, w500, w780, original

## 🛠️ Troubleshooting

### Common Issues

**"No TMDB ID" errors**
- Entries need a valid `tmdb` field to fetch replacement images
- Run TMDB update tasks to populate missing IDs

**API Rate Limits**
- The system includes delays between requests
- TMDB allows 40 requests per 10 seconds
- Large batch operations may take time

**Network Timeouts**
- Image validation has 10-second timeouts
- Some slow servers may appear as "broken"
- Re-run repair if needed

### Debugging
```ruby
# Test TMDB connectivity
tmdb = TmdbService.new
poster = tmdb.fetch_poster_url("550", "movie")
puts poster # Should return TMDB URL

# Test image validation
valid = tmdb.validate_image_url("https://example.com/image.jpg")
puts valid # true/false
```

## 🔒 Safety Features

- **Non-destructive**: Original URLs are only replaced after successful validation
- **Rollback friendly**: Changes are database updates, easily reversible
- **Error handling**: Comprehensive error catching and reporting
- **Rate limiting**: Built-in delays to respect API limits
- **Timeout protection**: Prevents hanging on slow/dead servers

## 📈 Best Practices

1. **Regular Maintenance**: Run `rails images:check` monthly
2. **Batch Processing**: Use off-peak hours for large repairs
3. **Monitoring**: Check repair results for patterns
4. **Backup**: Consider backing up before major repairs
5. **Testing**: Use `test_url` command for suspicious images

## 🎨 Customization

### Modify Image Size
Edit `app/services/tmdb_service.rb`, line ~71:
```ruby
"https://image.tmdb.org/t/p/w780#{poster_path}"  # Larger images
```

### Add Custom Validation
Extend the `validate_image_url` method in `TmdbService`:
```ruby
def validate_image_url(url)
  return false if url.blank?
  # Add custom validation logic here
  # ...existing code...
end
```

### Custom Repair Logic
Modify `ImageRepairService#repair_entry_image` for custom behavior.

## 📞 Support

If you encounter issues:
1. Check the Rails logs for detailed error messages
2. Verify your TMDB API key is working
3. Test individual URLs with the test command
4. Check network connectivity to TMDB servers

Happy image repairing! 🎉

