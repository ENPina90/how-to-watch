class UsersController < ApplicationController
  def toggle_dark_mode
    current_user.update!(dark_mode: !current_user.dark_mode)
    redirect_back(fallback_location: root_path)
  end

  def show
    @user = current_user
    load_statistics
  end

  # The half of the account that needs no password to change. Email and password go
  # through Devise's own form on the same page, which asks for the current password.
  def update
    @user = current_user

    if @user.update(profile_params)
      redirect_to profile_path, notice: 'Profile updated.'
    else
      load_statistics
      render :show, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(:username, :letterboxd_enabled, :auto_play, :auto_next)
  end

  def load_statistics
    entries = Entry.where(list_id: current_user.lists.select(:id))
    watched = current_user.user_entries.completed.select(:entry_id)

    @lists_count = current_user.lists.count
    @entries_count = entries.count
    # Counted over the user's own channels rather than everything they have ever tracked,
    # so it answers "what is left in my channels" and adds up with the number beside it.
    @unwatched_count = entries.where.not(id: watched).count
  end
end
