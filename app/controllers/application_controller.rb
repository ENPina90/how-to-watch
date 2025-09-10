class ApplicationController < ActionController::Base
  before_action :authenticate_user!, except: [:health]

  # Health check endpoint for Railway
  def health
    render json: {
      status: 'ok',
      timestamp: Time.current,
      environment: Rails.env
    }
  end
end
