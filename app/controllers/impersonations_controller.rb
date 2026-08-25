# Starts and ends "view as another user" for admins. See Impersonation for how the
# swapped `current_user` reaches the rest of the app.
class ImpersonationsController < ApplicationController
  before_action :require_admin_account, only: :create

  def create
    user = User.find(params[:id])

    if user == true_user
      redirect_back fallback_location: root_path,
                    alert: "You are already signed in as #{user.display_name}."
      return
    end

    session[Impersonation::IMPERSONATION_KEY] = user.id
    redirect_to root_path, notice: "Viewing the site as #{user.display_name}."
  end

  # Deliberately not admin-guarded: this only ever clears session state, and an admin
  # whose flag was revoked mid-session still needs a way out.
  def destroy
    session.delete(Impersonation::IMPERSONATION_KEY)
    redirect_to root_path, notice: "Back to your own account."
  end

  private

  # The real signed-in account, not `current_user` -- while impersonating a non-admin,
  # `current_user.admin?` is false, and switching straight to another user has to keep
  # working.
  def require_admin_account
    return if true_user&.admin?

    redirect_to root_path, alert: "Only admins can view the site as another user."
  end
end
