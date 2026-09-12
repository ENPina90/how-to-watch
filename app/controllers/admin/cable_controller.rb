# frozen_string_literal: true

module Admin
  # The cable dial's settings page: what is on the dial, in what order, and the two things
  # that rewrite what it is playing.
  #
  # /cable itself is a picture with a guide over it, and the guide had one admin button on
  # it -- rebuild. That was the only thing a page over a playing channel had room for, which
  # made it the only thing an admin could do to the dial: the line-up, its order, and which
  # channels were on it at all were a console job. This is the page those belong on, and the
  # guide now links here instead.
  #
  # Everything shown is read-only; the writes are all in CableChannelsController and in
  # CableController#regenerate. What the reads are for is not being asked to press those
  # blind: how many programmes a channel has to draw on, whether its days are actually laid
  # out, and what it is showing this second.
  class CableController < BaseController
    def show
      # Owners preloaded: the dial is single digits of rows, but the row says whose channel
      # it is and a query per row for that is a query per row.
      @channels = CableSchedule.channels.includes(:user).to_a
      @today = CableSchedule.today
      @tomorrow = @today + 1

      # The channels that could join the dial: public, and not already on it. An empty one
      # would be on air for about four seconds, so the entry count is shown beside the name
      # rather than the empty ones being hidden -- "can this fill a day" is a judgement, and
      # the number is what it is made from. Private channels are left out entirely: putting
      # one on the dial would show every account a list its owner chose not to share.
      @candidates = List.where(default: [false, nil], private: [false, nil]).order(:name).to_a
      @candidate_counts = counts_for(@candidates)

      @entry_counts = counts_for(@channels)
      @slot_counts = slot_counts
      # What each channel is showing right now, so the page says what the dial is doing
      # rather than only what it is set to. Same query the sidebar's Now Playing card uses.
      @on_air = CableSchedule.on_air_now.index_by { |row| row[:channel].id }

      # Counted the way the dashboard counts them, because a reel with no runtime is a reel
      # every break opens in roughly the same place on.
      @reels_total = CommercialReel.count
      @reels_timed = CommercialReel.where.not(duration_seconds: [nil, 0]).count

      @hide_sidebar = true
    end

    private

    # How much each of these channels has to draw on, as one query for the lot. The
    # candidate list is every public channel on the site, so a count per row is a hundred
    # queries rather than a handful.
    #
    # The entries a channel has, not the ones it can actually schedule: CableSchedule
    # .schedulable answers that properly but loads the whole watch sequence and preloads
    # three associations per channel to do it, which is a page-load's worth of work to put a
    # number in a column. The count that matters -- whether the days came out empty -- is
    # beside it in slot_counts, measured rather than predicted.
    def counts_for(lists)
      return {} if lists.empty?

      Entry.where(list_id: lists.map(&:id)).group(:list_id).count
    end

    # How many programmes each channel has been dealt for today and tomorrow, keyed
    # [list_id, date]. A channel with none for today is off air, which is the one state on
    # this page worth shouting about.
    def slot_counts
      return {} if @channels.empty?

      CableSlot.where(list_id: @channels.map(&:id), airs_on: [@today, @tomorrow])
               .group(:list_id, :airs_on).count
    end
  end
end
