class ApplicationController < ActionController::Base
  before_action :authenticate_user!, except: [:health]
  before_action :set_sidebar_defaults

  # Health check endpoint for Railway
  def health
    render json: {
      status: 'ok',
      timestamp: Time.current,
      environment: Rails.env
    }
  end

  private

  def set_sidebar_defaults
    # Default: sidebar is expanded and visible
    @sidebar_collapsed ||= false
    @hide_sidebar ||= false
    @now_playing_collapsed ||= false # Now Playing expanded by default
  end
end
