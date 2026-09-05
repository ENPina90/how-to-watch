# frozen_string_literal: true

# What the app has to tell you. Currently only provider-expiry warnings, which only admins
# are sent, but the page is everyone's -- the kinds that reach ordinary members (somebody
# subscribed to your channel, and so on) land here without needing a second page.
class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: :dismiss

  def index
    @notifications = Notification.visible_to(current_user).active.newest_first.includes(:subject)
    @dismissed_count = Notification.visible_to(current_user).where.not(dismissed_at: nil).count
  end

  def dismiss
    @notification.dismiss!

    # "View" on a kind that clears when you follow it -- see notification_view_dismisses?.
    # It is one button doing both halves so that a broken poster leaves the page the moment
    # you go and deal with it, rather than waiting for the next scan to retire it.
    if params[:view].present? && (target = helpers.notification_action_path(@notification))
      return redirect_to(target)
    end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@notification) }
      format.html { redirect_to notifications_path, notice: 'Dismissed.' }
    end
  end

  def dismiss_all
    Notification.visible_to(current_user).active.update_all(dismissed_at: Time.current)

    redirect_to notifications_path, notice: 'All caught up.'
  end

  private

  # Scoped through `visible_to` rather than found by id: it is the same check that decides
  # whether the notification may be *read*, so nobody can dismiss one addressed to somebody
  # else, or one of a kind they are not entitled to see.
  def set_notification
    @notification = Notification.visible_to(current_user).find(params[:id])
  end
end
