# 🖼️ Image Standardization System

## 🎯 **Smart Aspect Ratio Handling**

I've implemented an intelligent image standardization system that automatically applies the right transformations based on entry type, preventing stretching and compression issues.

## 📐 **Aspect Ratio Strategy**

### **Movie Posters** 🎬
- **Type**: `movie`, `fanedit`
- **Aspect Ratio**: 2:3 (tall poster format)
- **Dimensions**: 300×450px
- **Gravity**: `face` (focuses on faces/main subjects)
- **Perfect for**: Traditional movie poster artwork

### **Episode Images** 📺
- **Type**: `episode`
- **Aspect Ratio**: 16:9 (wide landscape format)
- **Dimensions**: 400×225px
- **Gravity**: `center` (balanced crop)
- **Perfect for**: Episode stills, landscape artwork

### **Series Images** 📚
- **Type**: `series`, `show`
- **Aspect Ratio**: 7:8 (balanced format)
- **Dimensions**: 350×400px
- **Gravity**: `face` (focuses on main characters)
- **Perfect for**: Series artwork, season posters

### **Default/Unknown** ❓
- **Type**: Any other type
- **Aspect Ratio**: 3:4 (balanced format)
- **Dimensions**: 300×400px
- **Gravity**: `center`
- **Perfect for**: Mixed or unknown content

## 🛠️ **How It Works**

### **Automatic Detection:**
```ruby
def entry_poster_image_tag(entry, options = {})
  # Automatically detects entry.media type
  # Applies appropriate transformations
  # Generates optimized Cloudinary URL
end
```

### **Cloudinary Transformations:**
```ruby
# Movies: "w_300,h_450,c_fill,g_face,q_auto,f_auto"
# Episodes: "w_400,h_225,c_fill,g_center,q_auto,f_auto"
# Series: "w_350,h_400,c_fill,g_face,q_auto,f_auto"
```

### **Generated URLs:**
```
# Movie poster
https://res.cloudinary.com/.../w_300,h_450,c_fill,g_face,q_auto,f_auto/shared/the_matrix_1999.jpg

# Episode image
https://res.cloudinary.com/.../w_400,h_225,c_fill,g_center,q_auto,f_auto/shared/breaking_bad_s01e01_2008.jpg
```

## 🎯 **Benefits**

### **✅ Perfect Aspect Ratios**
- **No stretching** - Images cropped intelligently to fit
- **No squashing** - Maintains proper proportions
- **Consistent display** - All images fit their containers perfectly

### **✅ Optimized Performance**
- **Auto format** - Cloudinary serves WebP/AVIF when supported
- **Auto quality** - Intelligent compression for smaller files
- **Lazy loading** - Images load only when needed

### **✅ Smart Cropping**
- **Face detection** for movies/series (focuses on actors)
- **Center cropping** for episodes (balanced composition)
- **Intelligent gravity** - Preserves most important parts

### **✅ Responsive Design**
- **Consistent dimensions** across all entry types
- **Predictable layouts** - No layout shifts from varying sizes
- **Professional appearance** - All images look intentionally sized

## 📱 **Visual Examples**

Based on your reference images:

### **Movie Poster (Godzilla Minus One):**
```
Original: Any size/ratio → 300×450px (2:3 poster ratio)
Crop: Focuses on main subject with face detection
Result: Perfect movie poster appearance
```

### **Episode Image (Wide format):**
```
Original: Any size/ratio → 400×225px (16:9 landscape ratio)
Crop: Center-focused for balanced composition
Result: Perfect episode thumbnail appearance
```

### **Series Poster (Star Wars):**
```
Original: Any size/ratio → 350×400px (7:8 balanced ratio)
Crop: Face detection for character focus
Result: Great series/season poster appearance
```

## 🎮 **Usage**

### **Automatic in Views:**
All your entry templates now use:
```erb
<%= entry_poster_image_tag(entry) %>
```

Instead of:
```erb
<%= image_tag(entry.poster.attached? ? entry.poster : entry.pic) %>
```

### **Custom Options:**
```erb
<%= entry_poster_image_tag(entry, class: 'custom-class', style: 'border-radius: 10px;') %>
```

### **Works Everywhere:**
- ✅ Entry cards in lists
- ✅ Individual entry pages
- ✅ All entry type partials (movie, episode, series, fanedit)
- ✅ Both uploaded posters and URL fallbacks

## ⚙️ **Cloudinary Transformations Explained**

### **Parameters Used:**
- `w_XXX` - Width in pixels
- `h_XXX` - Height in pixels
- `c_fill` - Crop to fill dimensions (no letterboxing)
- `g_face` - Focus on faces when cropping
- `g_center` - Center the crop area
- `q_auto` - Automatic quality optimization
- `f_auto` - Automatic format selection (WebP/AVIF when supported)

### **Smart Cropping:**
- **Face detection** ensures people remain visible in crops
- **Center gravity** provides balanced composition for landscapes
- **Fill crop** eliminates empty space and maintains aspect ratio

## 🔧 **Customization**

### **Adjust Dimensions:**
Edit `app/helpers/image_helper.rb` to change sizes:
```ruby
when 'movie', 'fanedit'
  "w_400,h_600,c_fill,g_face,q_auto,f_auto"  # Larger movie posters
```

### **Change Aspect Ratios:**
```ruby
when 'episode'
  "w_300,h_169,c_fill,g_center,q_auto,f_auto"  # Different episode ratio
```

### **Add New Types:**
```ruby
when 'documentary'
  "w_350,h_350,c_fill,g_center,q_auto,f_auto"  # Square format
```

## 🚀 **Ready to Deploy**

When you run the clean rebuild, all images will be:
- ✅ **Properly sized** for their entry type
- ✅ **Consistently formatted** across the app
- ✅ **Optimally compressed** by Cloudinary
- ✅ **Beautifully displayed** without stretching/squashing

```bash
# Clean rebuild with meaningful names AND proper sizing
rails posters:clean_and_rebuild
```

Your app will look professional and polished with perfectly sized, consistently formatted images! 🌟
