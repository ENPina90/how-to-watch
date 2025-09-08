# Letterboxd Integration Guide

This guide explains how to set up and use the Letterboxd integration in your How to Watch application.

## Overview

The Letterboxd integration allows users to:
- Connect their Letterboxd account via OAuth2
- Automatically sync completed movies/shows to Letterboxd as log entries
- Include ratings and reviews when syncing
- Bulk sync all completed entries at once

## Prerequisites

### 1. Letterboxd API Access

**Important**: As of January 2025, Letterboxd's API is not publicly available. You need to:

1. Visit https://letterboxd.com/api-coming-soon/
2. Request API access from Letterboxd
3. Once approved, you'll receive:
   - Client ID
   - Client Secret
   - API documentation access

### 2. Environment Variables

Add these to your `.env` file:

```bash
# Letterboxd API credentials
LETTERBOXD_CLIENT_ID=your_client_id_from_letterboxd
LETTERBOXD_CLIENT_SECRET=your_client_secret_from_letterboxd
LETTERBOXD_REDIRECT_URI=https://yourdomain.com/letterboxd/callback
```

For development, the redirect URI would be:
```bash
LETTERBOXD_REDIRECT_URI=http://localhost:3000/letterboxd/callback
```

## Setup Instructions

### 1. Run Database Migration

```bash
rails db:migrate
```

This adds the following fields to the users table:
- `letterboxd_access_token` (encrypted)
- `letterboxd_refresh_token` (encrypted)
- `letterboxd_token_expires_at`
- `letterboxd_user_id`
- `letterboxd_username`

### 2. Add Integration to User Interface

Include the Letterboxd integration partial in your user settings/profile page:

```erb
<!-- In your user settings view -->
<%= render 'shared/letterboxd_integration' %>
```

### 3. Add Sync Buttons to Entry Views

Add sync buttons to individual entry pages:

```erb
<!-- In entry show/watch views -->
<%= render 'shared/letterboxd_sync_button', entry: @entry %>
```

## Usage Flow

### For Users

1. **Connect Account**: Users click "Connect to Letterboxd" in their profile
2. **OAuth Flow**: Redirected to Letterboxd for authorization
3. **Automatic Sync**: When marking entries complete, they can sync to Letterboxd
4. **Bulk Sync**: Sync all completed entries at once

### For Developers

The integration provides several key methods:

```ruby
# Check if user is connected
current_user.letterboxd_connected?

# Sync a specific entry
current_user.sync_entry_to_letterboxd!(entry)

# Token management (automatic)
current_user.valid_letterboxd_token
current_user.refresh_letterboxd_token!
```

## API Mapping

### Your App → Letterboxd

| Your Field | Letterboxd Field | Notes |
|------------|------------------|-------|
| `user_entry.completed` | `watched: true` | Only completed entries sync |
| `user_entry.review` (1-10) | `rating` (0.5-5.0) | Converted: rating/2 |
| `user_entry.comment` | `review` | Text review content |
| `entry.imdb` | Film lookup | Used to find film on Letterboxd |
| `user_entry.completed_at` | `watchedDate` | When the entry was completed |

### Film Matching

The service attempts to match your entries to Letterboxd films by:
1. **IMDB ID** (most reliable)
2. **Title + Year search** (fallback)

## Error Handling

Common issues and solutions:

### "Could not find film on Letterboxd"
- The film might not exist in Letterboxd's database
- IMDB ID might be incorrect
- Title/year search didn't find a match

### "Invalid Letterboxd token"
- Token expired and refresh failed
- User needs to reconnect their account

### Rate Limiting
- Letterboxd may rate limit API calls
- Bulk sync includes delays between requests

## Security Considerations

- Access tokens are stored encrypted in the database
- Tokens are automatically refreshed when needed
- Users can disconnect at any time
- OAuth2 state parameter prevents CSRF attacks

## Testing

For development/testing without real Letterboxd API access:

1. Mock the LetterboxdService responses
2. Use VCR/WebMock for HTTP request stubbing
3. Test the OAuth flow with dummy tokens

## API Rate Limits

Letterboxd API rate limits (when available):
- Respect the rate limits in production
- Add delays between bulk operations
- Handle 429 responses gracefully

## Future Enhancements

Potential improvements:
- Automatic sync on completion (background job)
- Two-way sync (import from Letterboxd)
- Sync watchlist items
- Custom tags/lists synchronization

## Troubleshooting

### Connection Issues
1. Check environment variables
2. Verify redirect URI matches exactly
3. Ensure Letterboxd app is configured correctly

### Sync Failures
1. Check Rails logs for detailed error messages
2. Verify film exists on Letterboxd
3. Check token validity

### Development Setup
1. Use ngrok for local HTTPS testing
2. Update redirect URI in Letterboxd app settings
3. Test with a small number of entries first

## Support

For API access issues, contact Letterboxd directly through their API request form.
For integration issues, check the Rails logs and ensure all environment variables are set correctly.
