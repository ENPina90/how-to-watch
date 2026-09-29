# frozen_string_literal: true

# The guided tour, as far as the server is concerned: whether it is running, and the few
# facts the page cannot find out for itself -- which pages this visitor may reach, where
# the example channel lives, and the words from config/tour.yml.
#
# The tour's progress is a session cookie, `tour`, holding the page it is on. The page's
# controller writes it before each move and deletes it when the tour ends; the server only
# reads it, to decide whether to draw the tour at all. A cookie rather than a query string
# because /cable changes its own address as it plays, and would drop a parameter.
module TourHelper
  # The order the tour goes in. Each is one page; see tour_controller.js for its stops.
  TOUR_PAGES = %w[home channel results cable].freeze

  def tour_active?
    return false if mobile_request?

    params[:tour].present? || cookies[:tour].present?
  end

  # Whether there is enough of a tour for this visitor to be worth offering one: in the
  # secure access mode a signed-out visitor can reach none of it.
  def tour_available?
    return false if mobile_request?

    tour_pages(tour_channel).any?
  end

  def tour_config
    channel = tour_channel
    settings = tour_settings

    {
      pages: tour_pages(channel),
      signedIn: user_signed_in?,
      searchTerm: settings['search_term'].to_s,
      channelSearch: settings['channel_search'].to_s,
      paths: {
        home: root_path,
        channel: channel && list_path(channel),
        results: channel && list_path(channel, query: settings['channel_search']),
        cable: cable_path,
        signUp: new_user_registration_path
      },
      text: settings['text'] || {}
    }
  end

  private

  def tour_settings
    @tour_settings ||= YAML.load_file(Rails.root.join('config/tour.yml'))
  end

  # Found by name each time rather than by id, so the example survives being deleted and
  # re-made; private channels are never shown to a stranger, so never offered as one.
  def tour_channel
    return @tour_channel if defined?(@tour_channel)

    @tour_channel = List.where(private: [false, nil]).find_by(name: tour_settings['channel'])
  end

  def tour_pages(channel)
    TOUR_PAGES.select do |page|
      case page
      when 'home' then may_visit?('lists', 'index')
      when 'channel' then channel && may_visit?('lists', 'show')
      when 'results' then channel && tour_settings['channel_search'].present? && may_visit?('lists', 'show')
      when 'cable' then may_visit?('cable', 'show')
      end
    end
  end
end
