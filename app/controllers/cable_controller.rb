# frozen_string_literal: true

# /cable -- channels that are already running when you turn them on.
#
# Deliberately separate from EntriesController#watch, which this borrows its player and its
# channel-change machinery from but shares no logic with. The difference is not cosmetic:
#
#   * what plays is decided by the clock and CableSchedule, not by the viewer's position;
#   * every viewer sees the same programme at the same point, so nothing here reads
#     UserListPosition, UserEntryPosition or a stored player_progress...
#   * ...and nothing here writes them either. Turning on a channel is not watching in the
#     sense the rest of the app means it.
#
# Marking something watched is the one exception, and it goes through the ordinary
# entries#complete route -- that is a thing the viewer chose to do, not a side effect of the
# page having been rendered.
class CableController < ApplicationController
  before_action :set_channel, except: :guide

  # The listing behind the guide button: the whole dial at once, a few hours of it.
  #
  # Fetched when the guide is opened rather than rendered into every page. It is only ever
  # wanted on purpose, it is the same for everybody so it answers the same way each time,
  # and a grid built into the page would go stale sitting there while a channel played.
  def guide
    @window = CableSchedule.guide_window
    # The window runs four hours and so reaches into tomorrow every evening. Both days have
    # to exist or the grid stops dead at midnight; the job lays tomorrow out at noon, and
    # this covers the days before it has ever run.
    [@window.begin.to_date, @window.end.to_date].uniq.each do |date|
      CableSchedule.channels.each { |channel| CableSchedule.ensure_day!(channel, date) }
    end

    @now = Time.current
    @rows = CableSchedule.guide(at: @now)
    @playing = List.find_by(id: params[:channel])

    render partial: "cable/guide", formats: [:html]
  end

  def show
    # A day nobody laid out -- the first visit after a deploy, a channel marked default
    # this morning, a worker that was down at noon. Filling it here means the dial never
    # has a dead channel on it; `ensure_day!` leaves a schedule that already exists alone.
    #
    # Not while merely warming the channel below: a speculative fetch should not be what
    # decides a whole day's programme.
    CableSchedule.ensure_day!(@channel, CableSchedule.today) unless preloading?

    @now = Time.current
    @slot = CableSchedule.on_air(@channel, at: @now)

    # Off air: the channel has nothing that can be played at all. The view says so and
    # still offers the rest of the dial, which is more use than an error page.
    return render :off_air, layout: "special_layout" if @slot.nil?

    @entry = @slot.entry
    @current_subentry = @slot.subentry
    @upcoming = CableSchedule.upcoming(@channel, at: @slot.ends_at)

    # Joining midway is the entire point: the programme started at a clock time, and this
    # is how far it has got by now. Autoplay is on regardless of the channel's own setting
    # -- a cable channel that waits for a click is not a cable channel.
    @embed_url = @entry.embed_url(subentry: @current_subentry, autoplay: true,
                                  start_at: @slot.offset_at(@now))
    return render :off_air, layout: "special_layout" if @embed_url.blank?

    # The line-up in the sidebar, rather than this viewer's subscriptions: /cable is the
    # same set of channels for everybody.
    @cable_lineup = CableSchedule.channels.to_a

    # There is no entries sidebar here -- there is no list to step through -- so the layout
    # must not inset the page for one, and the collapse button must not sit where the watch
    # page's title-free corner lets it.
    @cable = true
    @sidebar_collapsed = true
    @hide_sidebar = false
    @now_playing_collapsed = false

    render layout: "special_layout"
  end

  private

  # The dial is the default channels and nothing else. An id that is not on it -- a channel
  # that stopped being default, a hand-edited URL -- lands on channel one rather than 404s,
  # which is what turning a dial past the end does.
  def set_channel
    @channel = CableSchedule.channels.find_by(id: params[:id]) || CableSchedule.channels.first

    return if @channel

    redirect_to root_path, alert: "There are no cable channels yet."
  end
end
