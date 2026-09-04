module ApplicationHelper
  # How many notifications are waiting. The navbar asks twice per page -- once for the dot
  # on the menu, once for the badge inside it -- so the count is worked out once per
  # request rather than once per caller.
  def unread_notification_count
    return 0 unless user_signed_in?

    @unread_notification_count ||= Notification.visible_to(current_user).active.count
  end

  # Which theme the page renders in. A signed-in user has said which they want; a signed-out
  # one has not, and users.dark_mode defaults to true, so the sign-in screens read dark like
  # the app they are the front door to -- rather than the cream fallback, which made them
  # look like a different site. The other page a signed-out visitor can reach, a vote room
  # on a TV, keeps the light fallback it was built against.
  def theme_class
    return current_user.dark_mode ? 'dark-mode' : 'light-mode' if user_signed_in?

    devise_controller? ? 'dark-mode' : 'light-mode'
  end

  # The grouping menu doubles as a direction toggle: clicking the criteria that is already
  # active flips it, and anything else starts ascending. The caret shows the direction the
  # list is currently in, not the one the link would switch to.
  def sort_menu_link(list, criteria, label = criteria)
    active = @criteria == criteria
    text = active ? safe_join([label, sort_direction_caret(@direction)], ' ') : label
    link_to text, list_path(list, criteria: criteria, sort: active && @direction == 'asc' ? 'desc' : 'asc')
  end

  def sort_direction_caret(direction)
    tag.i(class: "fa-solid fa-caret-#{direction == 'desc' ? 'down' : 'up'} sort-caret")
  end

  # Wires an element to the same Add to List modal the search results overlay opens. The
  # values go through the controller rather than straight onto data-imdb-id, because
  # list-search reads that dataset off the element the click was bound to -- and it can
  # only bind inside the navbar, which is where it lives.
  def add_to_list_data(imdb, title, poster, tmdb = nil)
    {
      data: {
        controller: 'add-to-list',
        action: 'add-to-list#open',
        add_to_list_imdb_value: imdb,
        add_to_list_tmdb_value: tmdb,
        add_to_list_title_value: title,
        add_to_list_poster_value: poster
      }
    }
  end

  # What the menu calls a grouping. The channel's own order is stored as Position and reads
  # as Order, which is the one place the two differ.
  CRITERIA_LABELS = { 'Position' => 'Order' }.freeze

  def criteria_label(criteria)
    CRITERIA_LABELS.fetch(criteria, criteria)
  end

  # What a section is called on screen. The key stays the raw value -- it is what the filter
  # matches on -- so the unit is added here rather than baked into it.
  def section_label(criteria, key)
    return "#{key} Min" if criteria == 'Length' && key.is_a?(Numeric)

    key
  end

  # A section is named by its key -- "Science Fiction", "1970s", 8.1 -- which is not a dom
  # id. These two turn a key into the ids the grouped view labels its section with, so a
  # card added without a reload can be put in the right one.
  def section_body_id(key)
    "section-body-#{section_slug(key)}"
  end

  # The section itself and its button in the rail, so emptying one can take both off the
  # page rather than leaving a heading over nothing and a filter that finds nothing.
  def section_id(key)
    "section-#{section_slug(key)}"
  end

  def section_filter_id(key)
    "section-filter-#{section_slug(key)}"
  end

  def section_count_id(key)
    "section-count-#{section_slug(key)}"
  end

  def section_slug(key)
    # A key of punctuation alone parameterizes to nothing; hash those rather than have
    # every one of them share an id.
    key.to_s.parameterize.presence || Digest::MD5.hexdigest(key.to_s)[0, 8]
  end

  def dom_id_for_partial(entry)
    "entry_#{entry.id}_partial"
  end

  # Helper method to check if current user can edit an entry
  # Works even when current_user is nil (for default lists)
  def can_edit_entry?(entry)
    return true if entry.list.default?
    return false unless current_user
    current_user.can_edit_entry?(entry)
  end

  # Helper method to check if current user can edit a list
  # Works even when current_user is nil (for default lists)
  def can_edit_list?(list)
    return true if list.default?
    return false unless current_user
    current_user.can_edit_list?(list)
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
