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
      return update_up_next(settings[:up_next_lead_seconds]) if settings.key?(:up_next_lead_seconds)

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

    # The bounds are not the interesting limit -- the one that matters is the completion
    # mark, and it cannot be checked here because it depends on the film. AppSetting
    # #up_next_mark_for applies it per runtime, so a lead longer than a short entry has
    # left in it is quietly pulled back rather than being a setting that does nothing.
    def update_up_next(seconds)
      AppSetting.update_up_next_lead!(seconds)

      redirect_to admin_dashboard_path,
                  notice: "Up next now appears #{helpers.pluralize(AppSetting.up_next_lead_seconds, 'second')} " \
                          'before the end, and counts down to it.'
    rescue ActiveRecord::RecordInvalid
      range = AppSetting::UP_NEXT_LEAD_RANGE
      redirect_to admin_dashboard_path,
                  alert: "Pick a whole number of seconds between #{range.begin} and #{range.end}."
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
