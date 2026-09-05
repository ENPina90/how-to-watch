# frozen_string_literal: true

require 'open-uri'
require 'net/http'
require 'json'

class EntriesController < ApplicationController
  include ActionView::RecordIdentifier
  before_action :set_list, only: %i[new create]
  before_action :set_entry, only: %i[show edit update duplicate destroy watch complete review complete_without_review reportlink repair_image migrate_poster shuffle_current decrement_current increment_current set_source fetch_posters update_poster update_position progress]
  # Everything here writes state shared by everyone who can see the entry -- its position
  # in the list, its provider, its poster, the `stream` flag. The per-user actions
  # (complete, review, shuffle_current and friends) are deliberately absent: they write
  # this user's own UserEntry/UserEntryPosition row, which a subscriber may do.
  before_action :check_edit_permissions,
                only: %i[edit update destroy update_poster
                         update_position reportlink set_source repair_image migrate_poster]
  # An entry is as private as the channel it lives in.
  before_action -> { refuse_guest_on_private!(@entry.list) }, only: %i[show watch]

  def new
    @entry = Entry.new
    @ids = @list.entries.map {|entry| "#{entry.id}-#{entry.imdb}"}.join('/')
  end

  def show
    @is_mobile = mobile_request?

    if @is_mobile
      render :show_mobile, layout: 'mobile'
      return
    end
  end

  def create
    if params[:custom]
      @entry = Entry.new(entry_params)
      @entry.list = @list
      @entry.position = @list.entries.count + 1
      @entry.media = 'fanedit' if @entry.media.blank?
      if @entry.save
        redirect_to list_path(@list)
        flash.now[:notice] = "#{@entry.name} successfully created"
      else
        flash.now[:notice] = "Something went wrong"
        render :new
      end
    else
      # Debug logging
      Rails.logger.info "Creating entry with params: #{params.inspect}"

      # Handle episode creation from TMDB first (when IMDB might be empty)
      if params[:season].present? && params[:episode].present? && params[:tmdb].present?
        Rails.logger.info "Handling episode from TMDB"
        handle_episode_from_tmdb
        return
      end

      # Handle the case where imdb is empty (shouldn't happen for movies/series)
      if params[:imdb].blank?
        Rails.logger.error "Invalid request parameters - imdb is blank"
        flash.now[:alert] = 'Invalid request parameters'
        render turbo_stream: turbo_stream.replace('flash', partial: 'shared/flashes')
        return
      end

      omdb_result = OmdbApi.get_movie(params[:imdb])

      # If OMDB returns nil (empty imdb or invalid), return error
      if omdb_result.nil?
        flash.now[:alert] = 'Could not find media with that ID'
        render turbo_stream: turbo_stream.replace('flash', partial: 'shared/flashes')
        return
      end

      omdb_result["tmdb"] = params[:tmdb]

      # Override media type to 'anime' if that's the type parameter
      if params[:type] == 'anime'
        omdb_result["Type"] = 'anime'
      end

      @entry = Entry.create_from_source(omdb_result, @list, false)
      if @entry.is_a?(Entry)
        if @entry.media == 'series' || @entry.media == 'anime'
          begin
            OmdbApi.get_series_episodes(@entry)
          rescue StandardError => e
            # The entry itself was created; only the episode import failed. Report the
            # real reason instead of guessing at a duplicate.
            Rails.logger.error "Failed to import episodes for Entry #{@entry.id}: #{e.class}: #{e.message}"
            flash.now[:alert] = "#{@entry.name} was added, but its episodes could not be imported: #{e.message}"
            render turbo_stream: turbo_stream.replace('flash', partial: 'shared/flashes')
            return
          end
        elsif @entry.media == 'movie' || @entry.media == 'fanedit'
          tmdb_service = TmdbService.new
          trailer_url = tmdb_service.fetch_trailer_url(@entry)
          @entry.update(trailer: trailer_url)
        end
        flash.now[:notice] = "#{@entry.name} added to #{@list.name}"
        partial = @entry.media == 'episode' ? "S#{@entry.season}E#{@entry.episode}" : @entry.imdb
        render turbo_stream: [
          turbo_stream.replace("header-count-#{@list.id}", partial: 'lists/header_count', locals: { count: @list.total_entry_count, list: @list }, action: :replace),
          turbo_stream.replace('flash', partial: 'shared/flashes'),
          turbo_stream.replace("entry_#{partial}_partial", partial: 'entries/remove_button', locals: { entry: @entry, partial: partial })
        ] + card_streams(@entry)
      else
        flash.now[:alert] = 'There was a problem'
        render turbo_stream: turbo_stream.replace('flash', partial: 'shared/flashes')
      end
    end
  end

  def edit
    @entry.streamable
    @user_lists = List.where(user: current_user)
    @entry.subentries.build if @entry.media == 'series' || @entry.media == 'anime'
    respond_to do |format|
      format.html
      format.text do
        render partial: 'entry_form',
               locals:  { entry: @entry, user_lists: @user_lists },
               formats: [:html]
      end
    end
  end

  def update
    old_position = @entry.position
    new_position = entry_params[:position].to_i

    # Clean up entry params - remove empty subentries
    cleaned_params = entry_params.to_h
    if cleaned_params[:subentries_attributes]
      cleaned_params[:subentries_attributes].each do |key, subentry_attrs|
        # Mark for destruction if name, season, and episode are all empty
        if subentry_attrs[:name].blank? && subentry_attrs[:season].blank? && subentry_attrs[:episode].blank?
          cleaned_params[:subentries_attributes][key][:_destroy] = '1'
        end
      end
    end

    cleaned_params.merge!(list: @entry.list)
    if @entry.update(cleaned_params)
      if old_position != new_position
        shift_positions(@entry, new_position)
      end
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(dom_id(@entry), partial: "entries/entry_#{@entry.media.downcase}", locals: { entry: @entry })
          turbo_stream.after(dom_id(@entry), "<turbo-frame id='modal-success'></turbo-frame>")
        end
        format.html { redirect_to list_path(@entry.list, anchor: @entry.imdb) }
      end
    else
      render :edit
    end
  end

  def duplicate
    new_entry = @entry.dup
    new_entry.list = current_user.lists.first
    if new_entry.save
      redirect_to edit_entry_path(new_entry)
    else
      flash[:error] = 'Failed to duplicate entry.'
      redirect_back(fallback_location: root_path)
    end
  end

  def destroy
    @entry = Entry.find(params[:id])
    @list = @entry.list
    name = @entry.name
    imdb = @entry.imdb
    source = params[:source]

    # Determine the partial key based on media type or imdb
    partial = @entry.media == 'episode' ? "S#{@entry.season}E#{@entry.episode}" : @entry.imdb

    flash.now[:notice] = "#{name} removed from #{@list.name}"
    # Read before it goes: which sections the page has it under, and what a completion
    # record says, are both gone a line later.
    memberships = section_memberships(@entry)
    @entry.destroy

    if source == 'show'
      # Use turbo_stream to replace the entry frame with the 'add_button' partial
      render turbo_stream: [
        turbo_stream.replace('flash', partial: 'shared/flashes'),
        turbo_stream.replace("header-count-#{@list.id}", partial: 'lists/header_count', locals: { count: @list.total_entry_count, list: @list }),
        turbo_stream.replace("entry-#{partial}-partial", partial: 'entries/add_button', locals: { list: @list, imdb_id: imdb, partial: partial })
      ]
    else
      respond_to do |format|
        format.html do
          redirect_to list_path(@list), notice: "#{name} was successfully deleted."
        end

        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace('flash', partial: 'shared/flashes'),
            turbo_stream.replace("header-count-#{@list.id}", partial: 'lists/header_count', locals: { count: @list.total_entry_count, list: @list }),
            turbo_stream.remove(dom_id(@entry)),
            # The order view wraps each card in a row of its own, which would otherwise
            # stay behind as an empty one.
            turbo_stream.remove("row-#{dom_id(@entry)}")
          ] + emptied_section_streams(memberships)
        end
      end
    end
  end

  def watch
    # The channel this is being watched *from*, which is not always the channel the entry
    # lives in: a channel that holds other channels lends their entries to its own page, and
    # clicking one there should keep you on that channel rather than dropping you into the
    # one it came from. The entry's own list stays its home -- editing, deleting and its
    # place in that channel all belong to it.
    @channel = watching_channel

    if current_user && !preloading?
      # Position is a number within the channel that owns the entry, so it is recorded
      # there. A borrowed entry has no position in the channel borrowing it.
      user_position = @entry.list.position_for_user!(current_user)
      user_position.update!(current_position: @entry.position)
    end

    # For series/anime, resolve the user's current episode (drives season/episode in the URL)
    if @entry.media == 'series' || @entry.media == 'anime'
      # Picking an episode from the sidebar asks for it by id. Recording it first means the
      # rest of this -- the embed url, the season and episode in the sidebar -- follows
      # from the same place a normal visit reads, rather than being patched in afterwards.
      chosen = @entry.subentries.find_by(id: params[:subentry]) if params[:subentry].present?
      @entry.update_user_subentry!(current_user, chosen) if chosen

      # Use user's current episode position instead of global entry.current. Signed out
      # there is nowhere to record the choice, so it holds for this request alone -- which
      # is all the sidebar's episode links need to work.
      @current_subentry = chosen || @entry.current_subentry_for_user(current_user)

      # Set episode sidebar variables based on user's current episode
      if @current_subentry
        @season = @current_subentry.season.to_i if @current_subentry.season.present?
        @episode = @current_subentry.episode.to_i if @current_subentry.episode.present?

        # For anime, use absolute episode number
        if @entry.media == 'anime'
          @episode = @current_subentry.calculate_absolute_episode_number
        end

        # Episode details are decoration on the player page: if TMDB is slow or down the
        # page still has to render, so a failure just leaves this nil.
        @current_episode =
          if @entry.tmdb.present? && @season && @episode
            begin
              TmdbService.new.fetch_episode(@entry.tmdb, @season, @episode)
            rescue TmdbService::RequestError => e
              Rails.logger.error "Error fetching episode details from TMDB: #{e.message}"
              nil
            end
          end
      end
    end

    # Computed embed URL, built on-demand from the resolved provider's template.
    @embed_url = @entry.embed_url(subentry: @current_subentry,
                                  autoplay: @channel.auto_play_for(current_user),
                                  start_at: start_position)
    if @embed_url.blank?
      flash[:alert] = "No video source available for this entry"
      redirect_to list_path(@entry.list) and return
    end

    # Set episode sidebar variables
    @tmdb_id = @entry.tmdb
    @imdb_id = @entry.imdb

    # The room follows the host. Reading this page is what moves it: the navigation
    # actions all redirect here, and the episode links in the sidebar arrive here
    # directly, so this is the one place that sees every change of what is playing.
    #
    # Except when the page is only being warmed. The host has not gone anywhere, so
    # moving the room would take everybody to a channel nobody chose -- and the host
    # would be the only one still watching what they thought they were all watching.
    @watch_party = current_watch_party
    unless preloading?
      follow_host_navigation(@watch_party, @entry, @current_subentry,
                             watch_entry_path(@entry, channel: @channel.id,
                                              subentry: @current_subentry&.id))
    end

    # Set sidebar states for watch page - both sidebars collapsed by default
    @sidebar_collapsed = true # Left sidebar collapsed
    @hide_sidebar = false # But still render it
    @now_playing_collapsed = false # Now Playing EXPANDED on watch page
    @entries_sidebar_collapsed = true # Right entries sidebar collapsed by default

    render layout: 'special_layout'
  end

  def decrement_current
    return redirect_to watch_entry_path(@entry) unless current_user

    if @entry.media == 'series' || @entry.media == 'anime'
      # Use user-level episode positioning
      user_position = UserEntryPosition.find_or_create_for(current_user, @entry)
      user_position.go_to_previous!

      if params[:mode] == 'watch'
        redirect_to watch_entry_path(@entry, channel: watching_channel.id)
      else
        redirect_to list_path(watching_channel, anchor: @entry.imdb)
      end
    else
      step_to(neighbour_in_channel(:previous))
    end
  end

  def increment_current
    return redirect_to watch_entry_path(@entry) unless current_user

    if @entry.media == 'series' || @entry.media == 'anime'
      # Use user-level episode positioning
      user_position = UserEntryPosition.find_or_create_for(current_user, @entry)
      user_position.advance_to_next!

      if params[:mode] == 'watch'
        redirect_to watch_entry_path(@entry, channel: watching_channel.id)
      else
        redirect_to list_path(watching_channel, anchor: @entry.imdb)
      end
    else
      step_to(neighbour_in_channel(:next))
    end
  end

  def shuffle_current
    return redirect_to watch_entry_path(@entry) unless current_user

    channel = watching_channel
    random_entry = shuffled_from(channel)

    if random_entry.nil?
      # No incomplete entries available, stay on current
      return redirect_to watch_entry_path(@entry, channel: channel.id)
    end

    # Position is a number within the channel that owns the entry, so it is only recorded
    # when the channel being shuffled is that one.
    if random_entry.list_id == channel.id
      channel.position_for_user!(current_user).update!(current_position: random_entry.position)
    end

    redirect_to watch_entry_path(random_entry, channel: channel.id)
  end

  def update_position
    visual_position = params[:position].to_i
    list = @entry.list

    # Get all entries in their current display order
    ordered_entries = list.all_items_by_position.select { |item| item.is_a?(Entry) }

    # Find the current visual position of this entry
    current_visual_position = ordered_entries.index(@entry) + 1

    # Clamp the visual position
    visual_position = [visual_position, 1].max
    visual_position = [visual_position, ordered_entries.count].min

    if current_visual_position == visual_position
      head :ok
      return
    end

    ActiveRecord::Base.transaction do
      # Normalize all positions first to ensure they're sequential
      list.normalize_entry_positions!

      # Now the database positions match visual positions
      # Reload entry to get normalized position
      @entry.reload

      shift_positions(@entry, visual_position)
      @entry.update!(position: visual_position)
    end

    head :ok
  end

  def complete
    # Check if entry is already completed by user
    if @entry.completed_by?(current_user)
      # Delete the UserEntry record to "uncomplete" it
      @entry.remove_user_tracking!(current_user)
    else
      # Mark as completed
      @entry.mark_completed_by!(current_user)

      # Advance user's position to next entry in the list
      if current_user
        list = @entry.list
        user_position = list.position_for_user!(current_user)

        # Find next entry by position
        next_entry = list.entries.where('position > ?', @entry.position)
                        .order(:position)
                        .first

        # Update position if there's a next entry
        if next_entry
          user_position.update!(current_position: next_entry.position)
        end
      end
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "completed-#{@entry.id}",
          partial: 'entries/completion_status',
          locals: { entry: @entry, user: current_user }
        )
      end
      format.html { redirect_back(fallback_location: list_path(@entry.list)) }
      format.json { head :ok }
    end
  end

  # The player saying where it has reached. Sent on pause, on seek, and once more as the
  # page goes away, so it answers with nothing at all: by the time a reply arrives the page
  # that asked is often already unloading, and there is nothing on screen to update.
  #
  # Only providers whose player talks to the page around it ever reach here -- see
  # docs/guides/VIDSRC.md §6. Signed out there is no position to record and the page leaves
  # the tracking off entirely; a session that lapses mid-film is a write like any other and
  # goes to the sign-in page, where nothing is listening for the answer.
  def progress
    current_user.user_entry_for!(@entry).record_progress!(
      params[:progress],
      duration: params[:duration],
      finished: params[:finished].to_s == 'true',
      unattended: params[:unattended].to_s == 'true'
    )

    head :no_content
  end

  def review
    # Mark as completed without triggering list navigation
    unless @entry.completed_by?(current_user)
      user_entry = @entry.user_entry_for!(current_user)
      user_entry.mark_completed!
      # Don't call @entry.mark_completed_by! as it triggers watched! which advances the list
    end

    user_entry = @entry.user_entry_for!(current_user)

    # Update review and comment
    if params[:review].present?
      user_entry.update(review: params[:review].to_i.clamp(1, 10))
    end

    if params[:comment].present?
      user_entry.update(comment: params[:comment])
    end

    # Handle "do not show again" option
    if params[:disable_reviews] == "true"
      @entry.list.update(reviewable: false)
      flash[:notice] = "Review prompts disabled for this channel"
    else
      flash[:notice] = "Thank you for your review!"
    end

    respond_to do |format|
      format.html { navigate_after_completion }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "completed-#{@entry.id}",
          partial: 'entries/completion_status',
          locals: { entry: @entry, user: current_user }
        )
      end
    end
  end

  def complete_without_review
    # Mark as completed without triggering list navigation
    unless @entry.completed_by?(current_user)
      user_entry = @entry.user_entry_for!(current_user)
      user_entry.mark_completed!
      # Don't call @entry.mark_completed_by! as it triggers watched! which advances the list
    end

    # Handle "do not show again" option
    if params[:disable_reviews] == "true"
      @entry.list.update(reviewable: false)
      flash[:notice] = "Review prompts disabled for this channel"
    end

    respond_to do |format|
      format.html { navigate_after_completion }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "completed-#{@entry.id}",
          partial: 'entries/completion_status',
          locals: { entry: @entry, user: current_user }
        )
      end
    end
  end

  def reportlink
    @entry.update(stream: !@entry.stream)
  end

  def repair_image
    result = @entry.repair_image!

    case result[:status]
    when :repaired
      flash[:notice] = "Image successfully repaired with TMDB poster"
    when :valid
      flash[:notice] = "Image is already working properly"
    when :failed
      flash[:alert] = "Could not find replacement image on TMDB"
    when :skipped
      flash[:alert] = result[:message]
    when :error
      flash[:alert] = "Error: #{result[:message]}"
    end

    redirect_back(fallback_location: entry_path(@entry))
  end

  def migrate_poster
    result = @entry.migrate_poster!

    case result[:status]
    when :migrated
      flash[:notice] = "Poster successfully migrated to Cloudinary (#{result[:filename]})"
    when :skipped
      flash[:notice] = result[:message]
    when :failed
      flash[:alert] = "Failed to migrate poster: #{result[:message]}"
    when :error
      flash[:alert] = "Error: #{result[:message]}"
    end

    redirect_back(fallback_location: entry_path(@entry))
  end

  def set_source
    source = Source.find_by(id: params[:source_id])

    if source && @entry.eligible_sources.include?(source)
      @entry.update!(provider: source)
    else
      flash[:alert] = "That source isn't available for this entry"
    end

    if params[:mode] == 'watch'
      redirect_to watch_entry_path(@entry)
    else
      redirect_back(fallback_location: entry_path(@entry))
    end
  end

  def fetch_posters
    posters = PosterCandidates.new(
      @entry,
      url_builder: ->(poster) {
        Rails.application.routes.url_helpers.rails_blob_url(poster, only_path: false, host: request.base_url)
      }
    ).call

    render json: { posters: posters }
  end

  # The picker saves either one of the candidates it offered, by URL, or a file the user
  # picked off their own machine -- the way out when none of the suggestions is any good.
  def update_poster
    result = if params[:poster].present?
               attach_uploaded_poster(params[:poster])
             elsif params[:poster_url].present?
               attach_poster_from_url(params[:poster_url])
             else
               { error: 'No poster provided' }
             end

    if result[:error]
      render json: result, status: :unprocessable_entity
    else
      render json: { success: true, message: 'Poster updated successfully' }
    end
  end

  private

    # What the picker accepts from a browser. An allowlist rather than a check for
    # "image/*": the file is served back to everyone who can see the entry, and
    # image/svg+xml is a way to hand them a script.
    POSTER_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
    MAX_POSTER_BYTES = 10.megabytes

    # {} on success, { error: } otherwise -- update_poster turns either into JSON.
    def attach_uploaded_poster(file)
      return { error: "That image is over #{MAX_POSTER_BYTES / 1.megabyte}MB" } if file.size > MAX_POSTER_BYTES

      # Sniffed rather than taken from the request: the content type a browser sends is
      # whatever the client chose to say, and this one decides what gets served back.
      content_type = Marcel::MimeType.for(file.tempfile, name: file.original_filename)
      return { error: 'That file is not a JPEG, PNG, WebP or GIF' } unless POSTER_CONTENT_TYPES.include?(content_type)

      @entry.poster.attach(
        io: file.tempfile,
        filename: poster_filename(content_type.split('/').last),
        content_type: content_type
      )
      {}
    rescue StandardError => e
      Rails.logger.error "Error attaching uploaded poster for entry #{@entry.id}: #{e.message}"
      { error: 'Failed to save that image' }
    end

    def attach_poster_from_url(poster_url)
      downloaded_image = URI.open(poster_url)
      extension = File.extname(URI.parse(poster_url).path).delete('.').presence || 'jpg'

      @entry.poster.attach(
        io: downloaded_image,
        filename: poster_filename(extension),
        content_type: downloaded_image.content_type || 'image/jpeg'
      )
      {}
    rescue StandardError => e
      Rails.logger.error "Error updating poster: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { error: 'Failed to update poster' }
    end

    def poster_filename(extension) = "poster_#{@entry.id}_#{Time.now.to_i}.#{extension}"

    # Which section this entry sits in under each grouping. A delete is a plain link on the
    # card, so unlike an add it carries no word about how the page is grouped -- this
    # answers for all of them and lets Turbo drop the ones that are not on the page.
    # `?channel=` says which channel the click came from. It is honoured only if that
    # channel really holds this entry -- directly or through the channels inside it --
    # so a hand-edited id cannot make one channel wear another's contents.
    # Where the player should pick up on this visit, for the member looking at it.
    #
    # Somewhere they have already been beats somewhere chosen for them: picking up where
    # you left off is a thing you asked for, and the randomiser is for entries you are
    # arriving at rather than returning to.
    def start_position
      resume_position || current_user&.random_start_for(@entry)
    end

    # A read: rendering the page must not create a tracking row (see
    # reads_do_not_write_spec), so this goes through the non-writing lookup and answers nil
    # for somebody who has never played this entry.
    def resume_position
      current_user&.user_entry_for(@entry)&.resume_position
    end

    def watching_channel
      asked = List.find_by(id: params[:channel])
      # `?channel=` names the channel being watched *from*, and the page reads its name,
      # its siblings and what is next on it. A private one is not a context a signed-out
      # visitor gets, even when the entry they asked for is public.
      asked = nil if asked&.private? && !user_signed_in?

      asked&.contains_entry?(@entry) ? asked : @entry.list
    end

    # The entry either side of this one on the channel being watched. On a channel that
    # borrows from the channels inside it that is one sequence across all of them -- which
    # is the whole point of the arrows saying "next on this channel" rather than "next in
    # whichever channel this entry happens to live in".
    def neighbour_in_channel(direction)
      channel = watching_channel

      # A channel that borrows nothing is its own positions, and asking the database for
      # one neighbour beats loading a thousand entries to look either side of one.
      if channel.child_lists.empty?
        return direction == :next ? @entry.next : @entry.previous
      end

      sequence = channel.watch_sequence
      at = sequence.index { |entry| entry.id == @entry.id }
      return nil if at.nil?

      direction == :next ? sequence[at + 1] : (at.positive? ? sequence[at - 1] : nil)
    end

    # Something else on this channel. A channel that borrows draws from everything under
    # it, so shuffling a channel of channels does not keep handing back the same one.
    def shuffled_from(channel)
      if channel.child_lists.empty?
        return channel.find_random_incomplete_entry_for_user(current_user, @entry)
      end

      channel.watch_sequence
             .reject { |entry| entry.id == @entry.id || entry.completed_by?(current_user) }
             .sample
    end

    # Onto the neighbour, or nowhere: an end of the channel leaves you where you are.
    def step_to(entry)
      redirect_to watch_entry_path(entry || @entry, channel: watching_channel.id)
    end

    def section_memberships(entry)
      ListsController::GROUPING_CRITERIA.to_h do |criteria|
        [criteria, entry.section_keys(criteria, user: current_user)]
      end
    end

    # After a delete, a section is either one shorter or gone. A heading over nothing and a
    # filter that finds nothing are both worse than no section at all.
    def emptied_section_streams(memberships)
      memberships.flat_map do |criteria, keys|
        keys.flat_map { |key| section_stream(criteria, key) }
      end
    end

    def section_stream(criteria, key)
      remaining = @list.entries.count do |entry|
        entry.section_keys(criteria, user: current_user).include?(key)
      end

      if remaining.zero?
        [turbo_stream.remove(helpers.section_id(key)), turbo_stream.remove(helpers.section_filter_id(key))]
      else
        [turbo_stream.replace(helpers.section_count_id(key),
                              helpers.tag.small("(#{remaining})", id: helpers.section_count_id(key)))]
      end
    end

    # Puts the new card on a channel page that is already open, so a search made from the
    # channel does not need a reload to show what it just added. Which container it belongs
    # in depends on how that page is grouped, which only the browser knows -- it posts
    # `criteria` along with the entry. Turbo drops a stream whose target is not on the
    # page, so an unopened channel and /entries/new both ignore these.
    def card_streams(entry)
      return [] unless entry.is_a?(Entry)

      criteria = params[:criteria].presence_in(ListsController::GROUPING_CRITERIA) || 'Position'
      card = helpers.entry_card(entry)

      if criteria == 'Position'
        # Wrapped the way the page wraps them, or the new card would be the one row the
        # category filters cannot hide.
        return [turbo_stream.append('list-entries',
                                    helpers.render('lists/position_item', item: entry))]
      end

      entry.section_keys(criteria, user: current_user).flat_map do |key|
        [turbo_stream.append(helpers.section_body_id(key), card), section_count_stream(key, criteria)]
      end
    end

    # The heading counts what is under it, and has just been made wrong.
    def section_count_stream(key, criteria)
      in_section = @list.entries.count do |entry|
        entry.section_keys(criteria, user: current_user).include?(key)
      end

      turbo_stream.replace(helpers.section_count_id(key),
                           helpers.tag.small("(#{in_section})", id: helpers.section_count_id(key)))
    end

    def handle_episode_from_tmdb
      importer = EpisodeImporter.new(
        list: @list,
        tmdb_id: params[:tmdb],
        season: params[:season],
        episode: params[:episode],
        imdb_id: params[:imdb].presence || params[:series_imdb].presence
      )
      result = importer.call
      partial = importer.dom_key

      case result[:status]
      when :created
        flash.now[:notice] = result[:message]
        render turbo_stream: [
          turbo_stream.replace("header-count-#{@list.id}", partial: 'lists/header_count', locals: { count: @list.total_entry_count, list: @list }, action: :replace),
          turbo_stream.replace('flash', partial: 'shared/flashes'),
          turbo_stream.replace("entry_#{partial}_partial", partial: 'entries/remove_button', locals: { entry: result[:entry], partial: partial })
        ] + card_streams(result[:entry])
      when :duplicate
        flash.now[:error] = result[:message]
        render turbo_stream: [
          turbo_stream.replace('flash', partial: 'shared/flashes'),
          turbo_stream.replace("entry_#{partial}_partial", partial: 'entries/remove_button', locals: { entry: result[:entry], partial: partial })
        ]
      else
        flash.now[:alert] = result[:message]
        render turbo_stream: turbo_stream.replace('flash', partial: 'shared/flashes')
      end
    end

    def set_list
      @list = List.find(params[:list_id])
    rescue ActiveRecord::RecordNotFound
      flash[:error] = 'Channel not found.'
      redirect_back(fallback_location: root_path)
    end

    def set_entry
      @entry = Entry.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      flash[:error] = 'Entry not found.'
      redirect_back(fallback_location: root_path)
    end

    def shift_positions(entry, new_position)
      list = entry.list

      if new_position < entry.position
        # If moving up, increment positions of entries between new and old positions
        list.entries.where(position: new_position...entry.position).update_all('position = position + 1')
      elsif new_position > entry.position
        # If moving down, decrement positions of entries between old and new positions
        list.entries.where(position: (entry.position + 1)..new_position).update_all('position = position - 1')
      end
    end

    def entry_params
      params.require(:entry).permit(
        :custom,
        :list_id,
        :position,
        :series,
        :note,
        :category,
        :name,
        :year,
        :pic,
        :poster,
        :genre,
        :director,
        :writer,
        :actors,
        :plot,
        :rating,
        :length,
        :media,
        :source_url,
        :provider_id,
        :source_key,
        :imdb,
        :tmdb,
        :language,
        :review,
        :season,
        :episode,
        :custom,
        subentries_attributes: [:id, :name, :plot, :imdb, :season, :episode, :rating, :length, :completed, :year, :_destroy]
      )
    end

    def navigate_after_completion
      return redirect_to watch_entry_path(@entry) unless current_user

      list = @entry.list

      # The UserEntry callback will have already advanced the user's position
      # So we just need to get the user's current entry and redirect to it
      current_entry = list.current_entry_for_user(current_user)

      if current_entry && current_entry != @entry
        redirect_to watch_entry_path(current_entry)
      else
        # No next entry available or position didn't advance, stay on current
        redirect_to watch_entry_path(@entry)
      end
    end

    # These are driven by `fetch`, not by navigation, and answer with a bare head. A
    # redirect would be followed by fetch and arrive as a 200, so the caller would read a
    # refusal as success.
    FETCH_DRIVEN_ACTIONS = %w[update_position reportlink].freeze

    def check_edit_permissions
      # Allow editing if user is authenticated and has permission, OR if entry is in a default list
      return if current_user&.can_edit_entry?(@entry) || @entry.list.default?

      if FETCH_DRIVEN_ACTIONS.include?(action_name)
        head :forbidden
      else
        redirect_to entry_path(@entry), alert: 'You do not have permission to perform this action.'
      end
    end

end
