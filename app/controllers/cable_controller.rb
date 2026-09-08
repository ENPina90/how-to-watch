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
    # Times are shown in the viewer's own zone. The schedule itself is a set of instants,
    # pinned in one fixed zone so everybody sees the same programme at the same moment --
    # but what time that moment *is* belongs to whoever is reading the listing.
    @zone = CableSchedule.resolve_zone(params[:tz])
    @window = CableSchedule.guide_window(in_zone: @zone)

    # A day of listings spans two or three cable days, and a day nobody laid out is a gap
    # in the middle of the grid. The job lays tomorrow out at noon; this covers the days
    # before it has ever run, and the day after tomorrow for a window that reaches it.
    CableSchedule.days_covered(@window).each do |date|
      CableSchedule.channels.each { |channel| CableSchedule.ensure_day!(channel, date) }
    end

    @now = Time.current
    @rows = CableSchedule.guide(at: @now, in_zone: @zone)
    @playing = List.find_by(id: params[:channel])
    @watched = watched_entry_ids(@rows)

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
    # What the HUD's arrows step through. They only change what the banner says, never what
    # is playing, so this is the running order either side of now and nothing more.
    @nearby = CableSchedule.nearby(@channel, at: @now)
    # Where this channel sits on the dial, which is what the badge shows. A channel is "3"
    # because of its place in the line-up, not because of its row id.
    @channel_number = CableSchedule.dial_number(@channel)

    # Joining midway is the entire point: the programme started at a clock time, and this
    # is how far it has got by now. Autoplay is on regardless of the channel's own setting
    # -- a cable channel that waits for a click is not a cable channel.
    # After the film ends the slot runs on to the next five-minute mark, and the gap is a
    # commercial break -- adverts from the film's own year, which is most of what makes the
    # break feel like it belongs to the channel. `filler` is the player saying the film has
    # finished early: a real channel cuts to the adverts rather than sitting on a black
    # frame until the clock catches up.
    # `filler` is the page saying the film is over -- either the player announced it, or the
    # file turned out to be shorter than the catalogue claimed and the schedule is asking for
    # a point past its end. A real channel cuts to the adverts; it does not play the last
    # minutes again from the top, which is what the player does when handed a start position
    # it cannot reach.
    @in_break = @slot.break_at?(@now) || params[:filler].present?

    if @in_break
      # A period we hold no reel for still gets its gap; the page puts a caption over it
      # rather than a dead frame.
      @embed_url = @slot.break_reel&.embed_url(start_at: @slot.reel_position_at(@now))
    else
      @embed_url = @entry.embed_url(subentry: @current_subentry, autoplay: true,
                                    start_at: @slot.offset_at(@now))
      return render :off_air, layout: "special_layout" if @embed_url.blank?
    end

    # When this channel next shows something else: the start of the break, or the start of
    # the next programme.
    @next_change_at = @in_break ? @slot.ends_at : @slot.next_change_after(@now)

    # No sidebars at all. There is no list to step through on the right, and the channel
    # list on the left is what the guide is for -- a permanent panel naming the same six
    # channels is furniture over a picture. What is left is the picture and the ring.
    @cable = true
    @sidebar_collapsed = true
    @hide_sidebar = true

    render layout: "special_layout"
  end

  private

  # Which of the entries in the listing this viewer has already seen, as one query for the
  # lot. Asking each entry in turn would be a query per cell, and a day of listings across
  # six channels runs to a few hundred.
  #
  # A read, and it stays one: nothing here creates a tracking row for an entry somebody has
  # merely seen the name of in a grid.
  def watched_entry_ids(rows)
    return Set.new unless current_user

    ids = rows.flat_map { |row| row[:slots].map(&:entry_id) }.uniq
    return Set.new if ids.empty?

    Set.new(UserEntry.where(user: current_user, entry_id: ids, completed: true).pluck(:entry_id))
  end

  # The dial is the default channels and nothing else. An id that is not on it -- a channel
  # that stopped being default, a hand-edited URL -- lands on channel one rather than 404s,
  # which is what turning a dial past the end does.
  def set_channel
    @channel = CableSchedule.channels.find_by(id: params[:id]) || CableSchedule.channels.first

    return if @channel

    redirect_to root_path, alert: "There are no cable channels yet."
  end
end
