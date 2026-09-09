# frozen_string_literal: true

module Admin
  # The reels that fill the gap between programmes on /cable, arranged by the years they
  # cover.
  #
  # They are somebody else's videos on somebody else's service, so the interesting question
  # is not what the row says but whether the thing still plays -- which is what `preview` is
  # for. Everything else here is ordinary CRUD.
  class CommercialReelsController < BaseController
    before_action :set_reel, only: %i[edit update destroy preview fetch_duration]

    # Grouped by decade rather than listed flat. The library is one reel a year through the
    # middle and one per era at the edges, so a decade is the unit that makes a gap visible:
    # a year with nothing behind it falls back to a neighbour, and that is worth seeing.
    def index
      @reels = CommercialReel.in_order.to_a
      @hide_sidebar = true
      @decades = @reels.group_by { |reel| (reel.starts_year / 10) * 10 }
      @gaps = missing_years
    end

    def new
      @reel = CommercialReel.new
      @hide_sidebar = true
    end

    def edit
      @hide_sidebar = true
    end

    def create
      @reel = CommercialReel.new(reel_params)

      if @reel.save
        redirect_to admin_commercial_reels_path, notice: "#{@reel.label} added."
      else
        @hide_sidebar = true
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @reel.update(reel_params)
        redirect_to admin_commercial_reels_path, notice: "#{@reel.label} saved."
      else
        @hide_sidebar = true
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      label = @reel.label
      @reel.destroy
      # `belongs_to :break_reel, optional: true` on CableSlot, so a schedule row that
      # pointed here keeps its gap and loses only the adverts in it.
      redirect_to admin_commercial_reels_path,
                  notice: "#{label} deleted. Breaks that were using it fall back to the caption."
    end

    # What this reel looks like when it comes up in a break: the same embed, at the same
    # sort of offset, for a gap the length of a real one.
    #
    # The offset is rolled fresh on every visit because that is the thing being tested --
    # a reel can be fine at one point and dead air at another, and a preview that always
    # opened at the same second would never show it.
    def preview
      @break_seconds = requested_break || rand(1..(CableSchedule::BREAK_GRID.to_i / 60)) * 60
      @offset = @reel.random_offset_for(@break_seconds)
      @embed_url = @reel.embed_url(start_at: @offset)
      @hide_sidebar = true

      render layout: 'application'
    end

    # How long the reel runs, read off YouTube. Its own button rather than something that
    # happens on save: it is an outbound request that can take seconds or fail, and neither
    # belongs in the middle of saving a form.
    #
    # It matters more than it looks. Without a runtime a break can only start somewhere in
    # the first few minutes -- see CommercialReel::BLIND_WINDOW -- so every break on the
    # channel opens with roughly the same adverts.
    def fetch_duration
      facts = YoutubeVideoFacts.for(@reel.youtube_id)

      if facts.duration_seconds.to_i.positive?
        @reel.update!(duration_seconds: facts.duration_seconds)
        redirect_to admin_commercial_reels_path,
                    notice: "#{@reel.label} runs #{helpers.reel_length(@reel)}."
      else
        redirect_to admin_commercial_reels_path,
                    alert: "Could not read a runtime for #{@reel.label}#{" -- #{facts.error}" if facts.error}."
      end
    end

    private

    def set_reel = @reel = CommercialReel.find(params[:id])

    def reel_params
      params.require(:commercial_reel)
            .permit(:label, :youtube_id, :starts_year, :ends_year, :duration_seconds)
    end

    # A break of a length the schedule could really produce. Only honoured within the grid,
    # because a preview of a gap longer than any gap can be is not a preview of anything.
    def requested_break
      seconds = params[:break].to_i
      return nil unless seconds.positive?

      [seconds, CableSchedule::BREAK_GRID.to_i].min
    end

    # Years inside the range the library covers that no reel answers for. A film from one
    # of these still gets adverts -- `for_year` falls to the nearest era -- but they are
    # the years where the adverts are least likely to belong to the film.
    def missing_years
      return [] if @reels.empty?

      covered = @reels.flat_map { |reel| (reel.starts_year..reel.ends_year).to_a }.to_set
      (@reels.first.starts_year..@reels.last.ends_year).reject { |year| covered.include?(year) }
    end
  end
end
