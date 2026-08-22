# 🔐 Environment Variables for Production Deployment

## 📋 **Required Environment Variables for Railway**

When deploying to Railway, you'll need to set these environment variables in your Railway project settings:

### **Rails Core Configuration**
```bash
RAILS_ENV=production
RAILS_HOST=yourdomain.com
RAILS_SERVE_STATIC_FILES=true
```

### **Rails Secrets**
Generate these locally and add to Railway:
```bash
# Generate a new master key
RAILS_MASTER_KEY=your_32_character_master_key

# Generate a new secret key base
SECRET_KEY_BASE=your_128_character_secret_key_base
```

**To generate these secrets locally:**
```bash
# For SECRET_KEY_BASE
rails secret

# For RAILS_MASTER_KEY
# Check your config/master.key file or generate new credentials:
rails credentials:edit
```

### **Cloudinary Configuration**
Use your existing Cloudinary URL (recommended approach):
```bash
CLOUDINARY_URL=cloudinary://api_key:api_secret@cloud_name
```

**Alternative (if you prefer individual variables):**
```bash
CLOUDINARY_CLOUD_NAME=your_cloudinary_cloud_name
CLOUDINARY_API_KEY=your_cloudinary_api_key
CLOUDINARY_API_SECRET=your_cloudinary_api_secret
```

### **Database & Redis**
Railway automatically provides these when you add the services:
```bash
# These are automatically set by Railway - don't set them manually
DATABASE_URL=postgresql://... (auto-generated)
REDIS_URL=redis://... (auto-generated)
```

### **Optional: TMDB API**
If your app uses The Movie Database API:
```bash
TMDB_API_KEY=your_tmdb_api_key
```

## 🚀 **How to Set Environment Variables in Railway**

1. **Go to your Railway project dashboard**
2. **Click on your app service**
3. **Navigate to "Variables" tab**
4. **Click "New Variable" for each variable**
5. **Add the variable name and value**

## 🔒 **Security Best Practices**

### **✅ DO:**
- Generate new secrets for production (don't reuse development secrets)
- Use Railway's built-in environment variable management
- Keep your Cloudinary credentials secure
- Use the same Cloudinary account across environments to avoid duplicate uploads

### **❌ DON'T:**
- Commit secrets to your Git repository
- Share production credentials in Slack/email
- Use development secrets in production
- Hardcode secrets in your code

## 🔍 **Verifying Environment Variables**

After deployment, you can verify your environment variables are working by:

1. **Check the health endpoint:** `https://yourdomain.com/health`
2. **Check Railway logs** for any environment-related errors
3. **Test Cloudinary uploads** by creating a new entry with an image

## 🛠️ **Troubleshooting**

### **Common Issues:**

**🚨 "Master key not found" error:**
- Ensure `RAILS_MASTER_KEY` is set in Railway variables
- Verify the master key is exactly 32 characters

**🚨 "Database connection failed":**
- Verify PostgreSQL service is added to your Railway project
- Railway automatically sets `DATABASE_URL` - don't override it

**🚨 "Cloudinary upload failed":**
- Check your Cloudinary credentials are correct
- Verify your Cloudinary account has sufficient quota

**🚨 "Assets not loading":**
- Ensure `RAILS_SERVE_STATIC_FILES=true` is set
- Check that assets were precompiled during deployment

## 📝 **Environment Variables Checklist**

Before deploying, ensure you have:

- [ ] `RAILS_ENV=production`
- [ ] `RAILS_HOST=yourdomain.com`
- [ ] `RAILS_SERVE_STATIC_FILES=true`
- [ ] `RAILS_MASTER_KEY=...` (32 characters)
- [ ] `SECRET_KEY_BASE=...` (128 characters)
- [ ] `CLOUDINARY_CLOUD_NAME=...`
- [ ] `CLOUDINARY_API_KEY=...`
- [ ] `CLOUDINARY_API_SECRET=...`
- [ ] PostgreSQL service added to Railway project
- [ ] Redis service added to Railway project (if using Action Cable)

## 🎯 **Quick Setup Commands**

Run these locally to generate secrets:

```bash
# Generate new secret key base
rails secret

# View your master key
cat config/master.key

# Test your environment setup locally
RAILS_ENV=production rails console
```

Then copy these values to your Railway project variables.
