class LetterboxdController < ApplicationController
  before_action :authenticate_user!

  # Initiate Letterboxd OAuth flow
  def connect
    service = LetterboxdService.new
    state = SecureRandom.hex(16)
    session[:letterboxd_state] = state

    authorization_url = service.authorization_url(state)
    redirect_to authorization_url, allow_other_host: true
  end

  # Handle OAuth callback from Letterboxd
  def callback
    # Verify state parameter to prevent CSRF attacks
    unless params[:state] == session[:letterboxd_state]
      flash[:alert] = "Invalid state parameter. Please try connecting again."
      redirect_to profile_path and return
    end

    session.delete(:letterboxd_state)

    if params[:error]
      flash[:alert] = "Letterboxd connection failed: #{params[:error_description] || params[:error]}"
      redirect_to profile_path and return
    end

    unless params[:code]
      flash[:alert] = "No authorization code received from Letterboxd."
      redirect_to profile_path and return
    end

    service = LetterboxdService.new
    token_response = service.exchange_code_for_token(params[:code])

    if token_response && token_response['access_token']
      # Get user profile from Letterboxd
      profile = service.get_user_profile(token_response['access_token'])

      current_user.update!(
        letterboxd_access_token: token_response['access_token'],
        letterboxd_refresh_token: token_response['refresh_token'],
        letterboxd_token_expires_at: Time.current + token_response['expires_in'].seconds,
        letterboxd_user_id: profile&.dig('id'),
        letterboxd_username: profile&.dig('username')
      )

      flash[:notice] = "Successfully connected to Letterboxd!"
      redirect_to profile_path
    else
      flash[:alert] = "Failed to connect to Letterboxd. Please try again."
      redirect_to profile_path
    end
  rescue StandardError => e
    Rails.logger.error("Letterboxd callback error: #{e.message}")
    flash[:alert] = "An error occurred while connecting to Letterboxd."
    redirect_to profile_path
  end

  # Disconnect from Letterboxd
  def disconnect
    current_user.disconnect_letterboxd!
    flash[:notice] = "Disconnected from Letterboxd."
    redirect_to profile_path
  end

  # Sync a specific entry to Letterboxd
  def sync_entry
    @entry = Entry.find(params[:entry_id])

    # Check if user has access to this entry (through list ownership or collaboration)
    unless can_access_entry?(@entry)
      flash[:alert] = "You don't have permission to sync this entry."
      redirect_back(fallback_location: root_path) and return
    end

    result = current_user.sync_entry_to_letterboxd!(@entry)

    if result[:error]
      flash[:alert] = result[:message]
    else
      flash[:notice] = result[:message]
    end

    redirect_back(fallback_location: entry_path(@entry))
  end

  # Bulk sync completed entries to Letterboxd
  def bulk_sync
    unless current_user.letterboxd_connected?
      flash[:alert] = "Please connect to Letterboxd first."
      redirect_to profile_path and return
    end

    completed_entries = current_user.user_entries.completed.includes(:entry)
    sync_results = { success: 0, failed: 0, errors: [] }

    completed_entries.find_each do |user_entry|
      result = current_user.sync_entry_to_letterboxd!(user_entry.entry)

      if result[:error]
        sync_results[:failed] += 1
        sync_results[:errors] << "#{user_entry.entry.name}: #{result[:message]}"
      else
        sync_results[:success] += 1
      end

      # Add small delay to avoid rate limiting
      sleep(0.5)
    end

    if sync_results[:success] > 0
      flash[:notice] = "Successfully synced #{sync_results[:success]} entries to Letterboxd."
    end

    if sync_results[:failed] > 0
      error_msg = "Failed to sync #{sync_results[:failed]} entries."
      if sync_results[:errors].any?
        error_msg += " Errors: #{sync_results[:errors].first(3).join(', ')}"
        error_msg += " and #{sync_results[:errors].count - 3} more..." if sync_results[:errors].count > 3
      end
      flash[:alert] = error_msg
    end

    redirect_to profile_path
  end

  private

  def can_access_entry?(entry)
    # User can access if they own the list or if it's a public/shared list
    entry.list.user == current_user || entry.list.public?
  end

  def profile_path
    # Adjust this to match your actual profile/settings path
    edit_user_registration_path
  end
end
