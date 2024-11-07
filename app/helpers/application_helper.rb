module ApplicationHelper
  def dom_id_for_partial(entry)
    "entry_#{entry.id}_partial"
  end

  def convert_to_embed_url(url)
    begin
      uri = URI.parse(url)
      video_id = nil

      case uri.host
      when 'www.youtube.com', 'youtube.com', 'm.youtube.com'
        if uri.path == '/watch'
          params = CGI.parse(uri.query || "")
          video_id = params['v']&.first
        elsif uri.path.start_with?('/embed/')
          # Already an embed URL
          video_id = uri.path.split('/embed/').last
        end
      when 'youtu.be'
        video_id = uri.path[1..-1] # Remove leading '/'
      else
        # Not a YouTube URL
        return url
      end

      if video_id
        # Build the embed URL with autoplay
        embed_uri = URI::HTTPS.build(
          host: 'www.youtube.com',
          path: "/embed/#{video_id}",
          query: 'autoplay=1'
        )
        return embed_uri.to_s
      else
        return url
      end
    rescue URI::InvalidURIError
      return url
    end
  end
end
