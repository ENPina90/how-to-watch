# frozen_string_literal: true

module Admin
  # Everything under /admin. The check is on `true_user`, not `current_user`: an admin
  # viewing the site as someone else is still an admin, but the dashboard is not part of
  # what they are looking at -- the same reasoning that keeps /sidekiq out of an
  # impersonated session.
  class BaseController < ApplicationController
    before_action :require_admin

    private

    def require_admin
      return if true_user&.admin? && !impersonating?

      redirect_to root_path, alert: 'That page is for admins.'
    end
  end
end
