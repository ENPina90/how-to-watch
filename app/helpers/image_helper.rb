module ImageHelper
  # Generate responsive image tags with appropriate transformations for different entry types
  def entry_poster_image_tag(entry, options = {})
    # Default options
    default_options = {
      alt: entry.name,
      class: 'entry-picture',
      loading: 'lazy'
    }

    # Always use raw img tags to completely bypass asset pipeline issues
    content_tag :img, nil, default_options.merge(options).merge(src: entry_poster_url(entry))
  end

  # The src the tag above will carry: an uploaded poster if there is one, the pic URL
  # otherwise. Kept public and separate from the tag so `rails posters:audit` can ask for
  # the same URL the page asks for -- an entry whose pic is broken still renders fine when
  # a poster is attached, and a poster whose Cloudinary asset went missing is broken even
  # though every column in the database looks filled in.
  def entry_poster_url(entry)
    if entry.poster.attached? && entry.poster.blob.service_name == 'cloudinary'
      generate_cloudinary_url_with_transformations(entry)
    elsif entry.poster.attached?
      entry.poster.url
    else
      entry.pic.to_s
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
