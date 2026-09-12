class ApplicationController < ActionController::Base
  # The two halves of the app a viewer can ask for by name. Anything else clears the
  # choice and puts them back on what their device suggests.
  VIEW_MODES = %w[mobile desktop].freeze

  include Impersonation
  include WatchPartyContext
  # Declares the before_action that replaces a blanket authenticate_user!: who gets in
  # without an account depends on AppSetting#access_mode.
  include AccessControl
  include VisitTracking

  before_action :set_sidebar_defaults
  before_action :configure_permitted_parameters, if: :devise_controller?

  # Views ask this to decide what to draw and where to point their links.
  helper_method :mobile_request?
  # What the sidebar's Now Playing card shows away from the player. Here rather than in a
  # helper because it keeps its place on the dial in the session, and the session is the
  # controller's to write.
  helper_method :cable_now_playing

  # Health check endpoint for Railway
  def health
    render json: {
      status: 'ok',
      timestamp: Time.current,
      environment: Rails.env
    }
  end

  # Swap between the phone view and the full one. A write -- it changes what every page
  # after it renders -- so it is a POST, and it goes back where it was pressed.
  def view_mode
    mode = params[:mode].to_s
    session[:view_mode] = VIEW_MODES.include?(mode) ? mode : nil

    redirect_back(fallback_location: root_path)
  end

  # What is on the dial this second, for the sidebar's Now Playing card: one row of
  # CableSchedule.on_air_now, or nil when every channel is off air.
  #
  # A rotation rather than a fixed channel. The card is the only window onto cable from
  # outside /cable, and pinning it to channel one would mean the rest of the dial was never
  # seen from anywhere else on the site. The place in the rotation lives in the session, so
  # it advances as the member moves around rather than jumping about within one page --
  # a random pick per render would re-draw a different channel on every turbo visit and
  # show the same one twice as often as not.
  #
  # Deliberately not cached across the request: the sidebar draws it once.
  def cable_now_playing
    dial = CableSchedule.on_air_now
    return nil if dial.empty?

    # Modulo the size we actually got, so a channel going off air -- or a new one being
    # marked default -- cannot leave the stored position pointing past the end.
    session[:cable_dial] = (session[:cable_dial].to_i + 1) % dial.size
    dial[session[:cable_dial]]
  end

  private

  # A speculative fetch: the player page one move away, pulled so it is warm if the viewer
  # goes there. Nothing has happened yet as far as they are concerned, so nothing may be
  # recorded -- a position moved in a channel they never opened would show up as the app
  # deciding for them where they were up to.
  #
  # Visits are handled by the header the fetch also sends: VisitTracking ignores XHR, which
  # is what a speculative fetch is.
  def preloading?
    request.headers['X-Cinema-Preload'].present?
  end

  # Devise permits only the credentials it knows about, so anything the account forms add
  # has to be listed here or it is dropped without a word -- which is what had been
  # happening to `username` since the field was added to the sign-up form.
  def configure_permitted_parameters
    extra = %i[username letterboxd_enabled]
    devise_parameter_sanitizer.permit(:sign_up, keys: extra)
    devise_parameter_sanitizer.permit(:account_update, keys: extra)
  end


  # Which half of the app to render: several pages have a phone-shaped view of their own.
  #
  # The user agent is a guess and the viewer's own choice is not, so a stored choice wins.
  # There is a way out of the phone view and a way back into it -- the phone view is
  # deliberately unable to play anything, and somebody who wants to watch on their phone
  # anyway should not have to find a different device to say so.
  #
  # In the session rather than a cookie: it is a preference about this visit, it costs
  # nothing to set again, and it disappears when they close the browser, which is the right
  # lifetime for "just this once, give me the big one".
  def mobile_request?
    return session[:view_mode] == 'mobile' if session[:view_mode].present?

    phone_user_agent?
  end

  def phone_user_agent?
    request.user_agent =~ /Mobile|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
  end

  def set_sidebar_defaults
    # Default: sidebar is expanded and visible
    @sidebar_collapsed ||= false
    @hide_sidebar ||= false
    @now_playing_collapsed ||= false # Now Playing expanded by default
  end
end
