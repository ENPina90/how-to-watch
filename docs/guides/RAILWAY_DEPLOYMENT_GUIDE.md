# 🚀 Railway Deployment Guide for How To Watch

## 🎯 **Why Railway?**

Railway is the perfect choice for your Rails application because:
- ✅ **Rails-native**: Built specifically for Rails deployments
- ✅ **All-in-one**: PostgreSQL, Redis, and deployment in one platform
- ✅ **Custom domains**: Easy integration with your Namecheap domain
- ✅ **Automatic SSL**: Free SSL certificates for your custom domain
- ✅ **Git-based deployments**: Automatic deploys from GitHub
- ✅ **Affordable**: Free tier available, $5/month for production

## 📋 **Pre-Deployment Checklist**

### 1. **Environment Variables Setup**
Create a `.env.production` file with these variables:
```bash
# Database (Railway will provide these automatically)
DATABASE_URL=postgresql://...

# Rails
RAILS_ENV=production
RAILS_MASTER_KEY=your_master_key_here
SECRET_KEY_BASE=your_secret_key_here

# Cloudinary (your existing credentials - single URL approach)
CLOUDINARY_URL=cloudinary://api_key:api_secret@cloud_name

# Your custom domain
RAILS_HOST=yourdomain.com
```

### 2. **Update Production Configuration**
Your `config/environments/production.rb` needs these updates:
```ruby
# Update the host for your domain
config.action_mailer.default_url_options = { host: ENV.fetch("RAILS_HOST", "yourdomain.com") }

# Enable static file serving for Railway
config.public_file_server.enabled = true

# Force SSL for production
config.force_ssl = true

# Set allowed hosts
config.hosts << ENV.fetch("RAILS_HOST", "yourdomain.com")
config.hosts << /.*\.railway\.app/
```

## 🚀 **Step-by-Step Deployment**

### **Phase 1: Railway Setup**

#### 1. **Create Railway Account**
- Go to [railway.app](https://railway.app)
- Sign up with GitHub (recommended for automatic deployments)

#### 2. **Create New Project**
- Click "New Project"
- Select "Deploy from GitHub repo"
- Connect your `how-to-watch` repository

#### 3. **Add PostgreSQL Database**
- In your Railway project dashboard
- Click "New" → "Database" → "Add PostgreSQL"
- Railway will automatically create `DATABASE_URL` environment variable

#### 4. **Add Redis (for Action Cable)**
- Click "New" → "Database" → "Add Redis"
- Railway will automatically create `REDIS_URL` environment variable

### **Phase 2: Environment Configuration**

#### 1. **Set Environment Variables**
In Railway project settings → Variables tab:

```bash
RAILS_ENV=production
RAILS_MASTER_KEY=<your_master_key>
SECRET_KEY_BASE=<generate_new_secret>
CLOUDINARY_URL=cloudinary://api_key:api_secret@cloud_name
RAILS_HOST=yourdomain.com
RAILS_SERVE_STATIC_FILES=true
```

#### 2. **Generate Secret Key Base**
Run locally to generate a new secret:
```bash
rails secret
```

### **Phase 3: Database Migration**

#### 1. **Run Migrations**
Railway will automatically run migrations, but you can also run them manually:
- Go to Railway project → your app service
- Open "Deployments" tab
- Click on latest deployment
- Use the terminal to run: `rails db:migrate`

#### 2. **Seed Data (Optional)**
If you want to import your development data:
```bash
rails db:seed
```

### **Phase 4: Custom Domain Setup**

#### 1. **Add Domain in Railway**
- Go to your Railway project
- Click on your app service
- Go to "Settings" tab
- Scroll to "Domains" section
- Click "Custom Domain"
- Enter your domain: `yourdomain.com`

#### 2. **Configure Namecheap DNS**
In your Namecheap domain management:

**Add these DNS records:**
```
Type: CNAME
Host: www
Value: your-app-name.railway.app

Type: A
Host: @
Value: 76.76.19.142 (Railway's IP)
```

**Or use Cloudflare (Recommended):**
1. Change nameservers in Namecheap to Cloudflare
2. Add domain to Cloudflare
3. Set DNS records in Cloudflare:
   - `CNAME www your-app-name.railway.app`
   - `CNAME @ your-app-name.railway.app`

#### 3. **SSL Certificate**
Railway automatically provisions SSL certificates for custom domains. This usually takes 5-10 minutes after DNS propagation.

## 🔧 **Production Optimizations**

### **1. Puma Configuration**
Update `config/puma.rb` for production:
```ruby
# Add at the top
workers ENV.fetch("WEB_CONCURRENCY") { 2 }
preload_app!

# Update threads for Railway
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Use Railway's PORT
port ENV.fetch("PORT") { 3000 }
```

### **2. Asset Compilation**
Railway automatically runs `rails assets:precompile`, but ensure your `application.rb` has:
```ruby
config.assets.initialize_on_precompile = false
```

### **3. Health Check Endpoint**
Create a health check for Railway:
```ruby
# config/routes.rb
Rails.application.routes.draw do
  get '/health', to: 'application#health'
  # ... your other routes
end

# app/controllers/application_controller.rb
def health
  render json: { status: 'ok', timestamp: Time.current }
end
```

## 📊 **Monitoring & Maintenance**

### **1. Railway Dashboard**
Monitor your app through Railway's dashboard:
- **Metrics**: CPU, Memory, Network usage
- **Logs**: Real-time application logs
- **Deployments**: Deployment history and status

### **2. Database Backups**
Railway automatically backs up your PostgreSQL database, but you can also:
```bash
# Create manual backup
pg_dump $DATABASE_URL > backup.sql

# Restore backup
psql $DATABASE_URL < backup.sql
```

### **3. Scaling**
Scale your application as needed:
- **Vertical scaling**: Upgrade Railway plan for more resources
- **Horizontal scaling**: Add more workers in Puma config

## 💰 **Pricing**

### **Free Tier**
- ✅ 500 hours/month execution time
- ✅ 1GB RAM
- ✅ 1GB disk
- ✅ PostgreSQL database
- ✅ Custom domain support

### **Pro Plan ($5/month)**
- ✅ Unlimited execution time
- ✅ 8GB RAM
- ✅ 100GB disk
- ✅ Multiple environments
- ✅ Priority support

## 🚨 **Troubleshooting**

### **Common Issues:**

1. **Assets not loading**
   - Ensure `RAILS_SERVE_STATIC_FILES=true`
   - Check asset compilation logs

2. **Database connection errors**
   - Verify `DATABASE_URL` is set automatically by Railway
   - Check database service is running

3. **SSL issues**
   - Wait for DNS propagation (up to 24 hours)
   - Verify DNS records are correct

4. **Environment variables not working**
   - Check Railway project variables
   - Ensure no typos in variable names

## ✅ **Deployment Checklist**

- [ ] Railway account created and connected to GitHub
- [ ] PostgreSQL database added to project
- [ ] Redis database added to project
- [ ] All environment variables configured
- [ ] Production configuration updated
- [ ] Custom domain added in Railway
- [ ] DNS records configured in Namecheap/Cloudflare
- [ ] SSL certificate provisioned
- [ ] Database migrations run
- [ ] Application accessible at custom domain
- [ ] All features working correctly

## 🎉 **You're Live!**

Once completed, your Rails application will be:
- ✅ **Deployed** on Railway's infrastructure
- ✅ **Accessible** at your custom Namecheap domain
- ✅ **Secured** with automatic SSL certificates
- ✅ **Scalable** with Railway's infrastructure
- ✅ **Monitored** through Railway's dashboard

Your app will automatically redeploy whenever you push changes to your main branch!

---

**Need help?** Railway has excellent documentation and support. You can also check the Railway logs for any deployment issues.
