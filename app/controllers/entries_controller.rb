# frozen_string_literal: true

require 'open-uri'

class EntriesController < ApplicationController
  include ActionView::RecordIdentifier
  skip_before_action :verify_authenticity_token
  before_action :set_list, only: %i[new create]
  before_action :set_entry, only: %i[show edit update duplicate destroy watch complete review complete_without_review reportlink repair_image migrate_poster shuffle_current decrement_current increment_current toggle_preferred_source fetch_posters update_poster]
  before_action :check_edit_permissions, only: %i[edit update destroy update_poster]

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
      @entry.source = fix_external_sources(entry_params["source"])
      @entry.list = @list
      @entry.position = @list.entries.count + 1
      @entry.media = 'fanedit' if @entry.media.empty?
      if @entry.save
        redirect_to list_path(@list)
        flash.now[:notice] = "#{@entry.name} successfully created"
      else
        flash.now[:notice] = "Something went wrong"
        render :new
      end
    else
      omdb_result = OmdbApi.get_movie(params[:imdb])
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
          rescue
            flash.now[:error] = "This already exists in your list"
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
          turbo_stream.replace("header-count-#{@list.id}", partial: 'lists/header_count', locals: { count: @list.entries.count, list: @list }, action: :replace),
          turbo_stream.replace('flash', partial: 'shared/flashes'),
          turbo_stream.replace("entry_#{partial}_partial", partial: 'entries/remove_button', locals: { entry: @entry, partial: partial })
        ]
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

    cleaned_params.merge!(list: @entry.list, source: fix_external_sources(cleaned_params["source"]))
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
    @entry.destroy

    if source == 'show'
      # Use turbo_stream to replace the entry frame with the 'add_button' partial
      render turbo_stream: [
        turbo_stream.replace('flash', partial: 'shared/flashes'),
        turbo_stream.replace("header-count-#{@list.id}", partial: 'lists/header_count', locals: { count: @list.entries.count, list: @list }),
        turbo_stream.replace("entry-#{partial}-partial", partial: 'entries/add_button', locals: { list: @list, imdb_id: imdb, partial: partial })
      ]
    else
      respond_to do |format|
        format.html do
          redirect_to entries_path, notice: "#{name} was successfully deleted."
        end

        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace('flash', partial: 'shared/flashes'),
            turbo_stream.replace("header-count-#{@list.id}", partial: 'lists/header_count', locals: { count: @list.entries.count, list: @list }),
            turbo_stream.remove(dom_id(@entry))
          ]
        end
      end
    end
  end

  def watch
    if current_user
      # Update user's current position to this entry
      user_position = @entry.list.position_for_user(current_user)
      user_position.update!(current_position: @entry.position)
    end

    # Check if we have a valid source to display
    preferred_source = @entry.preferred_source || @entry.list.preferred_source
    primary_source = preferred_source == 2 ? @entry.source_two : @entry.source
    fallback_source = preferred_source == 2 ? @entry.source : @entry.source_two

    # For series/anime, check subentry source
    if @entry.media == 'series' || @entry.media == 'anime'
      effective_source = @entry.current&.source || primary_source
    else
      effective_source = primary_source
    end

    # If primary source is nil, try fallback
    if effective_source.blank? && fallback_source.present?
      # Switch to fallback source
      @entry.update(preferred_source: preferred_source == 2 ? 1 : 2)
      flash[:notice] = "Primary source unavailable, switched to alternate source"
    elsif effective_source.blank?
      # No sources available at all
      flash[:alert] = "No video source available for this entry"
      redirect_to list_path(@entry.list) and return
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
      @entry.set_current(-1)
      if params[:mode] == 'watch'
        redirect_to watch_entry_path(@entry)
      else
        redirect_to list_path(@entry.list, anchor: @entry.imdb)
      end
    else
      list = @entry.list

      # Find previous entry by position (relative to current entry, not user's position)
      previous_entry = list.entries.where('position < ?', @entry.position)
                                  .order(position: :desc)
                                  .first

      if previous_entry
        # Navigate to previous entry - watch action will set position
        redirect_to watch_entry_path(previous_entry)
      else
        # No previous entry, stay on current
        redirect_to watch_entry_path(@entry)
      end
    end
  end

  # Keep the old decrement logic for when we actually want to mark as incomplete
  def mark_previous_incomplete
    if @entry.media == 'series'
      @entry.set_current(-1)
      if params[:mode] == 'watch'
        redirect_to watch_entry_path(@entry)
      else
        redirect_to list_path(@entry.list, anchor: @entry.imdb)
      end
    else
      if @entry.list.ordered
        @entry.mark_incomplete_by!(current_user)
        current = @entry.list.assign_current(:previous, current_user) if @entry.list.user == current_user
        redirect_to watch_entry_path(current || @entry)
      else
        list_positions = @entry.list.entries.map(&:position) - [@entry.list.current]
        random_entry_position = list_positions.sample
        current = @entry.list.assign_current(random_entry_position, current_user) if @entry.list.user == current_user
        redirect_to watch_entry_path(current || @entry)
      end
    end
  end

  def increment_current
    return redirect_to watch_entry_path(@entry) unless current_user

    if @entry.media == 'series' || @entry.media == 'anime'
      @entry.set_current(1)
      if params[:mode] == 'watch'
        redirect_to watch_entry_path(@entry)
      else
        redirect_to list_path(@entry.list, anchor: @entry.imdb)
      end
    else
      list = @entry.list

      # Find next entry by position (relative to current entry, not user's position)
      next_entry = list.entries.where('position > ?', @entry.position)
                              .order(:position)
                              .first

      if next_entry
        # Navigate to next entry - watch action will set position
        redirect_to watch_entry_path(next_entry)
      else
        # No next entry, stay on current
        redirect_to watch_entry_path(@entry)
      end
    end
  end

  def shuffle_current
    return redirect_to watch_entry_path(@entry) unless current_user

    list = @entry.list

    # Get a random incomplete entry for this user, excluding the current entry
    random_entry = list.find_random_incomplete_entry_for_user(current_user, @entry)

    if random_entry
      # Update user's position to the random entry
      user_position = list.position_for_user(current_user)
      user_position.update!(current_position: random_entry.position)

      redirect_to watch_entry_path(random_entry)
    else
      # No incomplete entries available, stay on current
      redirect_to watch_entry_path(@entry)
    end
  end

  def update_position
    @entry = Entry.find(params[:id])
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
        user_position = list.position_for_user(current_user)

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

  def review
    # Mark as completed without triggering list navigation
    unless @entry.completed_by?(current_user)
      user_entry = @entry.user_entry_for(current_user)
      user_entry.mark_completed!
      # Don't call @entry.mark_completed_by! as it triggers watched! which advances the list
    end

    user_entry = @entry.user_entry_for(current_user)

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
      flash[:notice] = "Review prompts disabled for this list"
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
      user_entry = @entry.user_entry_for(current_user)
      user_entry.mark_completed!
      # Don't call @entry.mark_completed_by! as it triggers watched! which advances the list
    end

    # Handle "do not show again" option
    if params[:disable_reviews] == "true"
      @entry.list.update(reviewable: false)
      flash[:notice] = "Review prompts disabled for this list"
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

  def toggle_preferred_source
    # Determine the new preferred_source value
    current_preferred = @entry.preferred_source || @entry.list.preferred_source
    new_preferred = current_preferred == 1 ? 2 : 1

    # Check if the target source is available
    target_source = new_preferred == 2 ? @entry.source_two : @entry.source

    if target_source.present?
      @entry.update!(preferred_source: new_preferred)

      if params[:mode] == 'watch'
        redirect_to watch_entry_path(@entry)
      else
        redirect_back(fallback_location: entry_path(@entry))
      end
    else
      flash[:alert] = "Alternative source not available"
      if params[:mode] == 'watch'
        redirect_to watch_entry_path(@entry)
      else
        redirect_back(fallback_location: entry_path(@entry))
      end
    end
  end

  def fetch_posters
    posters = []
    recent_images = []
    tmdb_service = TmdbService.new

    # Try TMDB first if we have a TMDB ID
    if @entry.tmdb.present?
      media_type = case @entry.media
                   when 'series', 'anime', 'episode'
                     'tv'
                   else
                     'movie'
                   end

      tmdb_poster = tmdb_service.fetch_poster_url(@entry.tmdb, media_type)
      if tmdb_poster
        posters << { url: tmdb_poster, source: 'TMDB' }
      end

      # Also fetch additional TMDB images
      begin
        tmdb_images_url = "https://api.themoviedb.org/3/#{media_type}/#{@entry.tmdb}/images?api_key=#{ENV['TMDB_API_KEY']}"
        response = Net::HTTP.get(URI(tmdb_images_url))
        images_data = JSON.parse(response)

        # Get top 4 posters from TMDB
        if images_data['posters']
          images_data['posters'].first(4).each do |poster|
            poster_url = "https://image.tmdb.org/t/p/w500#{poster['file_path']}"
            posters << { url: poster_url, source: 'TMDB' }
          end
        end
      rescue => e
        Rails.logger.error "Error fetching TMDB images: #{e.message}"
      end
    end

    # Try TMDB find endpoint with IMDB IDs to get alternative results
    [@entry.imdb, @entry.series_imdb].compact.uniq.each do |imdb_id|
      next if imdb_id.blank?

      begin
        # Use TMDB's find endpoint to search by external IMDB ID
        tmdb_find_url = "https://api.themoviedb.org/3/find/#{imdb_id}?api_key=#{ENV['TMDB_API_KEY']}&external_source=imdb_id"
        response = Net::HTTP.get(URI(tmdb_find_url))
        find_data = JSON.parse(response)

        # Check movie results
        if find_data['movie_results']&.any?
          poster_path = find_data['movie_results'].first['poster_path']
          if poster_path
            poster_url = "https://image.tmdb.org/t/p/w500#{poster_path}"
            posters << { url: poster_url, source: 'TMDB (via IMDB)' } unless posters.any? { |p| p[:url] == poster_url }
          end
        end

        # Check TV results
        if find_data['tv_results']&.any?
          poster_path = find_data['tv_results'].first['poster_path']
          if poster_path
            poster_url = "https://image.tmdb.org/t/p/w500#{poster_path}"
            posters << { url: poster_url, source: 'TMDB (via IMDB)' } unless posters.any? { |p| p[:url] == poster_url }
          end
        end
      rescue => e
        Rails.logger.error "Error fetching TMDB via IMDB ID #{imdb_id}: #{e.message}"
      end
    end

    # Try OMDB for BOTH imdb and series_imdb if they exist
    [@entry.imdb, @entry.series_imdb].compact.uniq.each do |imdb_id|
      next if imdb_id.blank?

      omdb_poster = tmdb_service.fetch_omdb_poster_url(imdb_id)
      if omdb_poster && !posters.any? { |p| p[:url] == omdb_poster }
        posters << { url: omdb_poster, source: 'OMDB' }
      end
    end

    # Get recent images from previous 2 entries in the same list
    if @entry.list.present?
      previous_entries = @entry.list.entries
                               .where('position < ?', @entry.position)
                               .order(position: :desc)
                               .limit(2)

      previous_entries.each do |prev_entry|
        if prev_entry.poster.attached?
          begin
            poster_url = if prev_entry.poster.service_name == 'cloudinary'
                          # Cloudinary URL
                          prev_entry.poster.url
                        else
                          # Local Active Storage URL
                          Rails.application.routes.url_helpers.rails_blob_url(prev_entry.poster, only_path: false, host: request.base_url)
                        end

            # Add to the end of the posters array with "Recent" label
            posters << {
              url: poster_url,
              source: "Recent: #{prev_entry.name}"
            }
          rescue => e
            Rails.logger.error "Error fetching poster for entry #{prev_entry.id}: #{e.message}"
          end
        end
      end
    end

    # Remove duplicates from posters
    posters.uniq! { |p| p[:url] }

    render json: { posters: posters }
  end

  def update_poster
    poster_url = params[:poster_url]

    if poster_url.blank?
      render json: { error: 'No poster URL provided' }, status: :unprocessable_entity
      return
    end

    begin
      # Determine the file extension from URL or default to jpg
      extension = File.extname(URI.parse(poster_url).path)
      extension = '.jpg' if extension.blank?

      # Download the image from the URL
      downloaded_image = URI.open(poster_url)

      # Attach it to the entry using Active Storage
      @entry.poster.attach(
        io: downloaded_image,
        filename: "poster_#{@entry.id}_#{Time.now.to_i}#{extension}",
        content_type: downloaded_image.content_type || 'image/jpeg'
      )

      render json: { success: true, message: 'Poster updated successfully' }
    rescue => e
      Rails.logger.error "Error updating poster: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: 'Failed to update poster' }, status: :unprocessable_entity
    end
  end

  private

    def mobile_request?
      request.user_agent =~ /Mobile|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
    end

    def set_list
      @list = List.find(params[:list_id])
    rescue ActiveRecord::RecordNotFound
      flash[:error] = 'List not found.'
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

    def fix_external_sources(url)
      if url.include?("mega")
        url.gsub("file", "embed")
      elsif url.include?("google")
        url.gsub("/view", "/preview")
      else
        return url
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
        :source,
        :source_two,
        :imdb,
        :tmdb,
        :language,
        :review,
        :season,
        :episode,
        :custom,
        subentries_attributes: [:id, :name, :plot, :imdb, :season, :episode, :rating, :length, :completed, :source, :year, :_destroy]
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

    def check_edit_permissions
      unless current_user&.can_edit_entry?(@entry)
        redirect_to entry_path(@entry), alert: 'You do not have permission to perform this action.'
      end
    end

end
