# frozen_string_literal: true

module Admin
  # The dashboard: what the site is doing, and the switches that change what it does.
  class DashboardController < BaseController
    def show
      @stats = AdminStatistics.new
      @setting = AppSetting.current
      @hide_sidebar = true
    end

    # The access mode, and whatever settings join it later. Kept on the dashboard rather
    # than given a page of its own: there is one row to edit and it is the point of the
    # page.
    def update
      mode = params.require(:app_setting).fetch(:access_mode, nil)

      unless AppSetting::ACCESS_MODES.include?(mode)
        return redirect_to admin_dashboard_path, alert: 'That is not one of the access modes.'
      end

      AppSetting.update_access_mode!(mode)

      redirect_to admin_dashboard_path, notice: "Site access is now #{mode}."
    end
  end
end
