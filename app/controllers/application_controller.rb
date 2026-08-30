class ApplicationController < ActionController::Base
  include Impersonation
  # Declares the before_action that replaces a blanket authenticate_user!: who gets in
  # without an account depends on AppSetting#access_mode.
  include AccessControl
  include VisitTracking

  before_action :set_sidebar_defaults
  before_action :configure_permitted_parameters, if: :devise_controller?

  # Health check endpoint for Railway
  def health
    render json: {
      status: 'ok',
      timestamp: Time.current,
      environment: Rails.env
    }
  end

  private

  # Devise permits only the credentials it knows about, so anything the account forms add
  # has to be listed here or it is dropped without a word -- which is what had been
  # happening to `username` since the field was added to the sign-up form.
  def configure_permitted_parameters
    extra = %i[username letterboxd_enabled]
    devise_parameter_sanitizer.permit(:sign_up, keys: extra)
    devise_parameter_sanitizer.permit(:account_update, keys: extra)
  end


  # Which half of the app to render: several pages have a phone-shaped view of their own.
  # Was defined identically in two controllers before a third needed it.
  def mobile_request?
    request.user_agent =~ /Mobile|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
  end

  def set_sidebar_defaults
    # Default: sidebar is expanded and visible
    @sidebar_collapsed ||= false
    @hide_sidebar ||= false
    @now_playing_collapsed ||= false # Now Playing expanded by default
  end
end
