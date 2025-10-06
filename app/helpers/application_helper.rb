module ApplicationHelper
  def dom_id_for_partial(entry)
    "entry_#{entry.id}_partial"
  end

  def find_now_playing_for_sidebar
    return nil unless current_user

    # Find the most recently watched entry
    recent_user_entry = current_user.user_entries
                                  .joins(:entry)
                                  .where.not(last_watched_at: nil)
                                  .order(last_watched_at: :desc)
                                  .first&.entry

    recent_position_entry = current_user.user_list_positions
                                      .joins(list: :entries)
                                      .order(updated_at: :desc)
                                      .first&.current_entry

    # Use the most recent between the two
    most_recent_entry = nil
    if recent_user_entry && recent_position_entry
      user_entry_time = current_user.user_entries.find_by(entry: recent_user_entry)&.last_watched_at || Time.at(0)
      position_time = current_user.user_list_positions.find_by(list: recent_position_entry.list)&.updated_at || Time.at(0)
      most_recent_entry = user_entry_time > position_time ? recent_user_entry : recent_position_entry
    elsif recent_user_entry
      most_recent_entry = recent_user_entry
    elsif recent_position_entry
      most_recent_entry = recent_position_entry
    end

    return nil unless most_recent_entry

    # Find the next entry in the same list
    list = most_recent_entry.list
    if list.ordered?
      next_entry = list.find_next_incomplete_entry_for_user(current_user, most_recent_entry.position)
    else
      next_entry = list.find_random_incomplete_entry_for_user(current_user, most_recent_entry)
    end

    next_entry || most_recent_entry
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
