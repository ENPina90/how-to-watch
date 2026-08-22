# 🏷️ Meaningful Cloudinary Filenames

## 🎯 **What Changed**

Instead of random blob keys like `9cv21q44tu968q72wjedi79lwk4b.jpg`, your Cloudinary files will now have meaningful names based on the entry name and year!

## 📝 **Filename Generation Logic**

### **Format:**
```
{clean_entry_name}_{year}.{extension}
```

### **Cleaning Process:**
1. **Take entry name** - e.g., "Godzilla Minus One"
2. **Remove special characters** - e.g., "Godzilla Minus One"
3. **Replace spaces with underscores** - e.g., "Godzilla_Minus_One"
4. **Convert to lowercase** - e.g., "godzilla_minus_one"
5. **Add year if available** - e.g., "godzilla_minus_one_2023"
6. **Add proper extension** - e.g., "godzilla_minus_one_2023.jpg"

## 📊 **Examples**

### **Movies:**
| Entry Name | Year | Generated Filename |
|------------|------|-------------------|
| "Godzilla Minus One" | 2023 | `godzilla_minus_one_2023.jpg` |
| "The Matrix" | 1999 | `the_matrix_1999.jpg` |
| "Fight Club" | 1999 | `fight_club_1999.jpg` |
| "Avengers: Endgame" | 2019 | `avengers_endgame_2019.jpg` |

### **TV Episodes:**
| Entry Name | Year | Generated Filename |
|------------|------|-------------------|
| "Breaking Bad S01E01" | 2008 | `breaking_bad_s01e01_2008.jpg` |
| "Game of Thrones: Winter is Coming" | 2011 | `game_of_thrones_winter_is_coming_2011.jpg` |

### **No Year Available:**
| Entry Name | Year | Generated Filename |
|------------|------|-------------------|
| "Some Old Movie" | null | `some_old_movie.jpg` |
| "Unknown Film" | null | `unknown_film.jpg` |

## 🛠️ **Technical Details**

### **Character Cleaning:**
```ruby
# Removes: !@#$%^&*()+=[]{}|;':"<>?/\
# Keeps: a-z A-Z 0-9 spaces - _
# Converts spaces to underscores
# Converts to lowercase
```

### **Length Limits:**
- **Base name**: Truncated to 50 characters
- **Total filename**: Usually under 60 characters
- **Cloudinary safe**: All characters are Cloudinary-compatible

### **Extension Handling:**
```ruby
# Preserves original extension if valid:
.jpg, .jpeg, .png, .gif, .webp

# Defaults to .jpg if:
# - No extension in original URL
# - Unknown/invalid extension
# - Error parsing URL
```

## 🎯 **Benefits**

### **✅ Organization**
- **Easy identification** in Cloudinary dashboard
- **Searchable filenames** based on movie/show names
- **Chronological organization** with years

### **✅ Debugging**
- **Clear connection** between database entries and Cloudinary files
- **Easy manual verification** in Cloudinary console
- **Obvious file purposes** when browsing assets

### **✅ SEO & Performance**
- **Descriptive filenames** for better SEO
- **Meaningful URLs** when images are accessed directly
- **Professional appearance** in browser dev tools

## 📱 **Example Cloudinary URLs**

### **Before (Random Keys):**
```
https://res.cloudinary.com/your-cloud/image/upload/v1757071223/shared/9cv21q44tu968q72wjedi79lwk4b.jpg
```

### **After (Meaningful Names):**
```
https://res.cloudinary.com/your-cloud/image/upload/v1757071223/shared/godzilla_minus_one_2023.jpg
```

## 🚀 **Ready to Use**

When you run the clean rebuild task, you'll see:

```bash
[1/150] (0.7%) Uploading: Godzilla Minus One...
   ✅ UPLOADED: Godzilla Minus One -> godzilla_minus_one_2023.jpg
[2/150] (1.3%) Uploading: The Matrix...
   ✅ UPLOADED: The Matrix -> the_matrix_1999.jpg
[3/150] (2.0%) Uploading: Breaking Bad S01E01...
   ✅ UPLOADED: Breaking Bad S01E01 -> breaking_bad_s01e01_2008.jpg
```

## 🎮 **Commands to Use**

```bash
# Clean rebuild with meaningful filenames
rails posters:clean_and_rebuild

# Check status
rails posters:status

# Future migrations will also use meaningful names
rails posters:migrate
```

Your Cloudinary dashboard will now be beautifully organized with recognizable, searchable filenames! 🎉

