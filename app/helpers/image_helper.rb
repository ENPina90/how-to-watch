module ImageHelper
  # Generate responsive image tags with appropriate transformations for different entry types
  def entry_poster_image_tag(entry, options = {})
    # Determine which image to use (uploaded poster or pic URL)
    image_source = entry.poster.attached? ? entry.poster : entry.pic

    # Default options
    default_options = {
      alt: entry.name,
      class: 'entry-picture',
      loading: 'lazy'
    }

    # Merge with provided options
    final_options = default_options.merge(options)

    # Always use raw img tags to completely bypass asset pipeline issues
    if entry.poster.attached? && entry.poster.blob.service_name == 'cloudinary'
      # Generate Cloudinary URL with transformations
      cloudinary_url = generate_cloudinary_url_with_transformations(entry)
      content_tag :img, nil, final_options.merge(src: cloudinary_url)
    else
      # Use the image source (either pic URL or poster attachment URL)
      image_url = if image_source.respond_to?(:url)
                    image_source.url  # Active Storage attachment
                  else
                    image_source.to_s  # String URL
                  end

      content_tag :img, nil, final_options.merge(src: image_url)
    end
  end

  private

  def generate_cloudinary_url_with_transformations(entry)
    # Extract cloud name from CLOUDINARY_URL
    cloud_name = extract_cloud_name_from_url
    base_url = "https://res.cloudinary.com/#{cloud_name}/image/upload"

    # Get transformation parameters based on entry type
    transformations = case entry.media&.downcase
                     when 'movie', 'fanedit'
                       # Movie posters: limit width, preserve aspect ratio
                       "w_300,c_scale,q_auto,f_auto"
                     when 'episode'
                       # Episodes: limit width, preserve aspect ratio
                       "w_400,c_scale,q_auto,f_auto"
                     when 'series', 'show'
                       # Series: limit width, preserve aspect ratio
                       "w_350,c_scale,q_auto,f_auto"
                     else
                       # Default: limit width, preserve aspect ratio
                       "w_300,c_scale,q_auto,f_auto"
                     end

    # Build the full URL
    "#{base_url}/#{transformations}/shared/#{entry.poster.key}"
  end

  def extract_cloud_name_from_url
    # Parse CLOUDINARY_URL format: cloudinary://api_key:api_secret@cloud_name
    return 'darepudnd' if ENV['CLOUDINARY_URL'].blank?  # Fallback to your cloud name

    begin
      uri = URI.parse(ENV['CLOUDINARY_URL'])
      uri.host  # This is the cloud name
    rescue StandardError
      'darepudnd'  # Fallback to your cloud name
    end
  end
end
