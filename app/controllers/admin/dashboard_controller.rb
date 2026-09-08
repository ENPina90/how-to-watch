# frozen_string_literal: true

module Admin
  # The dashboard: what the site is doing, and the switches that change what it does.
  class DashboardController < BaseController
    def show
      @stats = AdminStatistics.new
      @setting = AppSetting.current
      @deployment = DeploymentStatus.new
      # Labelled with the slug as well as the name: several of these are called some
      # variation of "VidSrc" and picking the wrong one moves every channel.
      # Ordered by name after position, because positions collide in practice and an
      # arbitrary order would put a different provider first on different page loads.
      @imdb_source_options = Source.active.where(kind: 'imdb').order(:position, :name)
                                   .map { |source| ["#{source.name} (#{source.slug})", source.id] }
      @channel_breakdown = channel_breakdown
      @hide_sidebar = true
    end

    # The access mode, and whatever settings join it later. Kept on the dashboard rather
    # than given a page of its own: there is one row to edit and it is the point of the
    # page.
    def update
      settings = params.require(:app_setting)

      # Two forms post here, each carrying only its own field, so whichever arrived is the
      # one being changed.
      return update_up_next(settings[:up_next_percent]) if settings.key?(:up_next_percent)

      mode = settings.fetch(:access_mode, nil)

      unless AppSetting::ACCESS_MODES.include?(mode)
        return redirect_to admin_dashboard_path, alert: 'That is not one of the access modes.'
      end

      AppSetting.update_access_mode!(mode)

      redirect_to admin_dashboard_path, notice: "Site access is now #{mode}."
    end

    # Move every channel onto one provider. Worth a button because the alternative is
    # editing channels one at a time, and the case it exists for -- a provider domain dying
    # -- is the case where that is least affordable.
    def reset_source
      source = Source.active.find_by(id: params[:source_id], kind: 'imdb')

      if source.nil?
        return redirect_to admin_dashboard_path,
                           alert: 'Pick an active provider that plays by IMDb id.'
      end

      result = ChannelSourceReset.call(source)

      redirect_to admin_dashboard_path, notice: reset_summary(result, source)
    end

    # The weekly sweeps, run by hand. Enqueued rather than run here: between them they make
    # a few hundred outbound requests and take minutes, which is not a request cycle. What
    # they find lands in notifications either way, which is where it lands on a Monday too.
    def run_poster_scan
      BrokenPosterScanJob.perform_later

      redirect_to admin_dashboard_path,
                  notice: 'Poster scan started. Broken posters will appear in your notifications.'
    end

    def run_embed_scan
      EmbedAvailabilityScanJob.perform_later

      redirect_to admin_dashboard_path,
                  notice: 'Stream check started. Unplayable entries will appear in your notifications.'
    end

    private

    # The floor is the completion mark and it is not arbitrary: below it the fullscreen
    # route to the up-next card stops firing, silently. See AppSetting::UP_NEXT_RANGE.
    def update_up_next(percent)
      AppSetting.update_up_next_percent!(percent)

      redirect_to admin_dashboard_path,
                  notice: "Up next now appears #{AppSetting.current.up_next_percent}% of the way through."
    rescue ActiveRecord::RecordInvalid
      floor = (AppSetting::UP_NEXT_RANGE.begin * 100).round
      redirect_to admin_dashboard_path,
                  alert: "Pick a percentage between #{floor} and 100. Earlier than #{floor}% is before " \
                         'a film counts as watched, and the card would stop appearing for anyone in fullscreen.'
    end

    def reset_summary(result, source)
      summary = "#{helpers.pluralize(result.channels, 'channel')} now plays through #{source.name}."
      return summary if result.entries.zero?

      "#{summary} Cleared #{helpers.pluralize(result.entries, 'entry')} that overrode their channel."
    end

    # What the channels are pointed at right now, so the button is not being pressed blind.
    # Sources are loaded once rather than per group -- there are a handful of them.
    def channel_breakdown
      sources = Source.all.index_by(&:id)

      List.group(:provider_id).count
          .map { |id, count| [sources[id], count] }
          .sort_by { |_source, count| -count }
    end
  end
end
