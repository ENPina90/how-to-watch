# frozen_string_literal: true

class ListsController < ApplicationController
  before_action :set_list, only: [:show, :edit, :update, :destroy, :watch_current, :top_entries, :move_to_list, :subscribe, :unsubscribe, :mark_all_complete, :mark_all_incomplete]
  before_action :check_edit_permissions, only: [:edit, :update, :destroy, :mark_all_complete, :mark_all_incomplete]

  def index
    # Sidebar starts expanded by default on index page
    @sidebar_collapsed = false

    # Check if this is a mobile request
    @is_mobile = mobile_request?

    if @is_mobile
      # For mobile, find the user's favorites list (mobile: true)
      @favorites_list = current_user.lists.find_by(mobile: true)
      # Get all subscribed lists with entry counts
      @subscribed_lists = current_user.subscribed_lists
                                    .left_joins(:entries)
                                    .group('lists.id')
                                    .select('lists.*, COUNT(entries.id) as entries_count')
                                    .order('lists.name ASC')
      render :index_mobile, layout: 'mobile'
      return
    end

    # Order lists by most recent UserEntry activity (watching/reviewing)
    lists_with_activity = List.joins(entries: :user_entries)
                              .where(user_entries: { user: current_user })
                              .group('lists.id')
                              .order('MAX(user_entries.created_at) DESC')
                              .includes(:entries, :user)

    # Get IDs of lists with activity to exclude them from the second query
    active_list_ids = lists_with_activity.pluck(:id)

    # Also include lists with no user entries, ordered by creation date
    lists_without_activity = List.where.not(id: active_list_ids)
                                 .order(created_at: :desc)
                                 .includes(:entries, :user)

    # Combine both sets: active lists first, then inactive lists
    @lists = lists_with_activity.to_a + lists_without_activity.to_a

    List.where(ordered: false).each{|unordered_list| unordered_list.assign_current(:next) }
  end

  def new
    @list = List.new
    @list.parent_list_id = params[:parent_list_id] if params[:parent_list_id].present?
  end

  def create
    # @list = current_user.lists.build(list_params)
    @list = List.new(list_params.except(:parent_list_id))
    @list.user = current_user
    @list.current = 0

    if @list.save
      # Add to parent list if specified
      if params[:list][:parent_list_id].present?
        parent_list = List.find(params[:list][:parent_list_id])
        if @list.add_to_parent(parent_list)
          redirect_to list_path(parent_list), notice: "List '#{@list.name}' was successfully created and added to #{parent_list.name}."
        else
          redirect_to lists_path, notice: "List '#{@list.name}' was successfully created but could not be added to the parent list."
        end
      else
        redirect_to lists_path, notice: 'List was successfully created.'
      end
    else
      render :new
    end
  end

  def show
    # Sidebar starts expanded by default on show page (you can change to true to start collapsed)
    @sidebar_collapsed = false

    load_entries
    @is_mobile = mobile_request?
    @minimal = params[:view] == "minimal" || @is_mobile
    @current = @list.find_entry_by_position(:current) unless @list.entries.empty?
    @random_selection = @list_entries.sample(3)

    if @is_mobile
      # Get all subscribed lists with entry counts for mobile search
      @subscribed_lists = current_user.subscribed_lists
                                    .left_joins(:entries)
                                    .group('lists.id')
                                    .select('lists.*, COUNT(entries.id) as entries_count')
                                    .order('lists.name ASC')
      render :show_mobile, layout: 'mobile'
      return
    end

    respond_to do |format|
      format.html
      format.text do
        render partial: 'entries',
               locals: {
                 minimal: @minimal,
                 entries: @entries,
                 sections: @sections,
                 random_selection: @random_selection,
                 list_entries: @list_entries
               },
               formats: [:html]
      end
    end
  end

  def edit; end

  def update
    if @list.update(list_params)
      redirect_to list_path(@list), notice: 'List was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @list.destroy
    redirect_to root_path, notice: "#{@list.name} was successfully destroyed."
  end

  def watch_current
    if @list.entries.empty?
      redirect_to list_path(@list), notice: "This list has no entries to watch. Add some entries first!"
    else
      @list.update(current: @list.entries.first.position) if @list.current.nil?
      current_entry = @list.find_entry_by_position(:current)

      if current_entry
        redirect_to watch_entry_path(current_entry)
      else
        # Fallback logic based on list type and user status
        if current_user
          fallback_entry = if @list.ordered?
            # For ordered lists, find the first incomplete entry
            @list.find_next_incomplete_entry_for_user(current_user, 0)
          else
            # For unordered lists, find a random incomplete entry
            @list.find_random_incomplete_entry_for_user(current_user)
          end

          if fallback_entry
            # Update user's position and list's current position
            user_position = @list.position_for_user(current_user)
            user_position.update_to_entry!(fallback_entry)
            @list.update!(current: fallback_entry.position)

            message = @list.ordered? ?
              "Current entry not found. Starting from your next unwatched entry." :
              "Current entry not found. Here's something you haven't watched yet!"
            redirect_to watch_entry_path(fallback_entry), notice: message
          else
            redirect_to list_path(@list), notice: "You've completed all entries in this list!"
          end
        else
          # For guest users, just pick the first entry
          first_entry = @list.entries.order(:position).first
          redirect_to watch_entry_path(first_entry), notice: "Current entry not found. Starting from the beginning."
        end
      end
    end
  end

  def top_entries
    tmdb_service = TmdbService.new
    series_imdb_id = tmdb_service.fetch_imdb_id(params[:tmdb], 'show')
    scraper = ImdbScraper.new(@list, series_imdb_id)
    episodes = scraper.fetch_episode_imdb_ids_with_ratings
    counter = 0
    episodes.each do |episode|
      break if counter == params[:top_number].to_i || counter == 20
      puts "Fetcing movie ##{counter + 1} data"
      omdb_result = OmdbApi.get_movie(episode[:imdb_id])
      next if omdb_result.nil?
      next if !!(omdb_result["Title"] =~ /\s[Pp]art\s/)
      omdb_result["seriesID"] = series_imdb_id
      omdb_result["imdbRating"] = episode[:rating]
      @entry = Entry.create_from_source(omdb_result, @list, false)
      next unless @entry.is_a?(Entry)
      @entry.update(series: scraper_results[:title]) if @entry.series.nil?
      counter += 1
    end
    flash[:notice] = "#{ActionController::Base.helpers.pluralize(counter, 'episode')} of #{@list.entries.last&.series} added"
    redirect_to list_path(@list)
  end

  def move_to_list
    target_list_id = params[:target_list_id]
    remove_from_id = params[:remove_from]

    if remove_from_id.present?
      # Remove from specific parent
      parent_list = List.find(remove_from_id)
      @list.remove_from_parent(parent_list)
      flash[:notice] = "#{@list.name} has been removed from #{parent_list.name}"
      redirect_to list_path(@list)
    elsif target_list_id.blank?
      # Remove from all parent lists (make it a top-level list)
      @list.remove_from_all_parents
      flash[:notice] = "#{@list.name} has been removed from all parent lists"
      redirect_to list_path(@list)
    else
      target_list = List.find(target_list_id)

      # Validate the move
      unless @list.can_be_added_to?(target_list)
        flash[:alert] = "Cannot add #{@list.name} to #{target_list.name}. This would create a circular reference or it's already added."
        redirect_to list_path(@list) and return
      end

      # Ensure user owns the target list
      unless target_list.user == current_user
        flash[:alert] = "You don't have permission to add lists to #{target_list.name}"
        redirect_to list_path(@list) and return
      end

      # Add the list to the new parent (this creates a new relationship, doesn't remove existing ones)
      if @list.add_to_parent(target_list)
        flash[:notice] = "#{@list.name} has been added to #{target_list.name}"
        redirect_to list_path(target_list)
      else
        flash[:alert] = "Failed to add #{@list.name} to #{target_list.name}"
        redirect_to list_path(@list)
      end
    end
  end

  def subscribe
    if current_user.subscribe_to!(@list)
      flash[:notice] = "Subscribed to #{@list.name}"
    else
      flash[:alert] = "Already subscribed to #{@list.name}"
    end

    respond_to do |format|
      format.html { redirect_to list_path(@list) }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "subscription-#{@list.id}",
          partial: 'lists/subscription_button',
          locals: { list: @list, user: current_user }
        )
      end
    end
  end

  def unsubscribe
    list_name = @list.name
    current_user.unsubscribe_from!(@list)

    if params[:redirect_to_sibling] == "true"
      # Find next subscribed list with unwatched content
      next_list = @list.find_sibling(:next, current_user)

      if next_list && next_list != @list
        flash[:notice] = "You have unsubscribed from #{list_name}"
        redirect_to list_watch_current_path(next_list)
      else
        # No other subscribed lists, go to main lists page
        flash[:notice] = "You have unsubscribed from #{list_name}. No other subscribed lists with unwatched content."
        redirect_to lists_path
      end
    else
      flash[:notice] = "Unsubscribed from #{list_name}"

      respond_to do |format|
        format.html { redirect_to list_path(@list) }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "subscription-#{@list.id}",
            partial: 'lists/subscription_button',
            locals: { list: @list, user: current_user }
          )
        end
      end
    end
  end

  def mark_all_complete
    entries_count = @list.entries.count

    @list.entries.each do |entry|
      entry.mark_completed_by!(current_user) unless entry.completed_by?(current_user)
    end

    flash[:notice] = "Marked all #{entries_count} entries as complete"
    redirect_to edit_list_path(@list)
  end

  def mark_all_incomplete
    entries_count = @list.entries.count

    @list.entries.each do |entry|
      entry.mark_incomplete_by!(current_user) if entry.completed_by?(current_user)
    end

    flash[:notice] = "Marked all #{entries_count} entries as incomplete"
    redirect_to edit_list_path(@list)
  end

  def add_to_favorites
    # Find the user's favorites list (mobile: true)
    favorites_list = current_user.lists.find_by(mobile: true)

    unless favorites_list
      render json: { error: 'Favorites list not found' }, status: 404
      return
    end

    # Create the entry using the same logic as the regular add to list
    imdb_id = params[:imdb]
    tmdb_id = params[:tmdb]

    # Use the existing entry creation logic
    begin
      omdb_result = OmdbApi.get_movie(imdb_id)
      if omdb_result.nil?
        render json: { error: 'Movie not found' }, status: 404
        return
      end

      # Add TMDB ID if provided
      omdb_result["tmdb_id"] = tmdb_id if tmdb_id.present?

      entry = Entry.create_from_source(omdb_result, favorites_list, false)

      if entry.is_a?(Entry)
        render json: {
          success: true,
          message: "Added to #{favorites_list.name}",
          entry_id: entry.id
        }
      else
        render json: { error: 'Failed to create entry' }, status: 500
      end
    rescue => e
      Rails.logger.error "Error adding to favorites: #{e.message}"
      render json: { error: 'Failed to add to favorites' }, status: 500
    end
  end

  def add_to_list
    # Find the specified list
    list = current_user.lists.find_by(id: params[:list_id])

    unless list
      render json: { error: 'List not found' }, status: 404
      return
    end

    # Check if user can edit this list
    unless current_user.can_edit_list?(list)
      render json: { error: 'You do not have permission to add to this list' }, status: 403
      return
    end

    # Create the entry using the same logic as the regular add to list
    imdb_id = params[:imdb]
    tmdb_id = params[:tmdb]

    # Use the existing entry creation logic
    begin
      omdb_result = OmdbApi.get_movie(imdb_id)
      if omdb_result.nil?
        render json: { error: 'Movie not found' }, status: 404
        return
      end

      # Add TMDB ID if provided
      omdb_result["tmdb_id"] = tmdb_id if tmdb_id.present?

      entry = Entry.create_from_source(omdb_result, list, false)

      if entry.is_a?(Entry)
        render json: {
          success: true,
          message: "Added to #{list.name}",
          entry_id: entry.id
        }
      else
        render json: { error: 'Failed to create entry' }, status: 500
      end
    rescue => e
      Rails.logger.error "Error adding to list: #{e.message}"
      render json: { error: 'Failed to add to list' }, status: 500
    end
  end

  # def watch_random
  #   watch_path(@list.find_entry_by_position(:random))
  # end

  private

  def mobile_request?
    request.user_agent =~ /Mobile|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
  end

  def set_list
    @list = List.find(params[:id] || params[:list_id])
  end

  def load_entries
    @list_entries = if params[:query].present?
                      @list.entries.search_by_input(params[:query])
                    else
                      @list.entries
                    end

    # Load child lists with their positions in this parent context
    @child_lists = @list.child_relationships.includes(:child_list).order(:position).map do |rel|
      child = rel.child_list
      child.define_singleton_method(:position) { rel.position }
      child
    end

    @entries = {}
    @criteria = params[:criteria].present? ? params[:criteria] : 'Position'
    filter_entries(@criteria)
     @entries = @entries.transform_keys { |key| key.nil? ? 'Other' : key }
    @sections = params[:sort].present? ? @entries.keys.sort.reverse : @entries.keys.sort

    return unless @list.user == current_user

    @list.update(settings: params[:criteria], sort: params[:sort])
  end

  def filter_entries(criteria)
    case criteria
    when 'Genre'
      genres = @list_entries.flat_map { |entry| entry.genre.split(',').map(&:strip) }.uniq.sort
      genres.each do |genre|
        @entries[genre] = @list_entries.select { |entry| entry.genre.include?(genre) }
      end
    when 'Year'
      (1900..Date.today.year).step(10) do |year|
        decade_entries = @list_entries.select { |entry| entry.year >= year && entry.year < year + 10 }
        @entries["#{year}s"] = decade_entries unless decade_entries.empty?
      end
    when 'Watched'
      @entries['Unwatched'] = @list_entries.reject { |entry| entry.completed_by?(current_user) }.sort_by(&:position)
      @entries['Watched'] = @list_entries.select { |entry| entry.completed_by?(current_user) }.sort_by(&:position)
    else
      @entries = @list_entries.group_by { |entry| entry.send(criteria.downcase) }
    end
  end

  def list_params
    permitted = [:name, :ordered, :private, :sort, :parent_list_id, :reviewable, :preferred_source, :auto_play, :auto_next]
    permitted << :default if current_user&.can_set_default?
    params.require(:list).permit(permitted)
  end

  def check_edit_permissions
    unless current_user&.can_edit_list?(@list)
      redirect_to lists_path, alert: 'You do not have permission to perform this action.'
    end
  end

  def find_now_playing_entry
    # Find the most recently watched entry
    recent_user_entry = current_user.user_entries
                                  .joins(:entry)
                                  .where.not(last_watched_at: nil)
                                  .order(last_watched_at: :desc)
                                  .first&.entry

    recent_position_entry = current_user.user_list_positions
                                      .joins(list: :entries)
                                      .order(updated_at: :desc)
                                      .first&.current_entry

    # Use the most recent between the two
    most_recent_entry = nil
    if recent_user_entry && recent_position_entry
      user_entry_time = current_user.user_entries.find_by(entry: recent_user_entry)&.last_watched_at || Time.at(0)
      position_time = current_user.user_list_positions.find_by(list: recent_position_entry.list)&.updated_at || Time.at(0)
      most_recent_entry = user_entry_time > position_time ? recent_user_entry : recent_position_entry
    elsif recent_user_entry
      most_recent_entry = recent_user_entry
    elsif recent_position_entry
      most_recent_entry = recent_position_entry
    end

    return nil unless most_recent_entry

    # Find the next entry in the same list
    list = most_recent_entry.list
    if list.ordered?
      next_entry = list.find_next_incomplete_entry_for_user(current_user, most_recent_entry.position)
    else
      next_entry = list.find_random_incomplete_entry_for_user(current_user, most_recent_entry)
    end

    next_entry || most_recent_entry
  end
end
