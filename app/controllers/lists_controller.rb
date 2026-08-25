# frozen_string_literal: true

class ListsController < ApplicationController
  # The grouping options offered on the list page. Everything except Position, Genre,
  # Year and Watched is handled by reading the matching Entry attribute, so this doubles
  # as the whitelist for that lookup.
  GROUPING_CRITERIA = %w[Position Genre Year Watched Rating Category Media Length].freeze

  before_action :set_list, only: [:show, :edit, :update, :destroy, :watch_current, :top_entries, :add_season, :move_to_list, :subscribe, :unsubscribe, :mark_all_complete, :mark_all_incomplete]
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

    # Category 1: Your Lists (created by current user)
    # `includes(:entries)` used to load every entry of every list just so the card could
    # call .count; the cards only need a count and the user's stored position.
    @your_lists = with_card_data(current_user.lists).order(created_at: :desc)

    # Category 2: Recently Watched (lists with completed entries)
    @recently_watched_lists = with_card_data(
      List.joins(entries: :user_entries).where(user_entries: { user: current_user, completed: true })
    ).group('lists.id').order('MAX(user_entries.completed_at) DESC').limit(20)

    # Category 3: Community Lists (created by other users)
    # Show: public lists OR subscribed lists OR (if admin) all lists
    if current_user.admin?
      # Admins see all lists created by other users (including private)
      @community_lists = with_card_data(List.where.not(user_id: current_user.id))
                         .order(created_at: :desc).limit(20)
    else
      # Regular users see public lists OR subscribed lists
      community_list_ids = List.where.not(user_id: current_user.id)
                               .where(private: [false, nil])
                               .pluck(:id) +
                           List.where.not(user_id: current_user.id)
                               .joins(:subscriptions)
                               .where(subscriptions: { user_id: current_user.id })
                               .pluck(:id)

      @community_lists = with_card_data(List.where(id: community_list_ids.uniq))
                         .order(created_at: :desc).limit(20)
    end
  end

  def search
    query = params[:q]

    if query.present?
      # Search lists by name (public lists OR user's own lists)
      public_lists = List.where('name ILIKE ?', "%#{query}%").where(private: [false, nil])
      own_lists = List.where('name ILIKE ?', "%#{query}%").where(user_id: current_user.id)
      list_ids = (public_lists.pluck(:id) + own_lists.pluck(:id)).uniq

      lists = List.where(id: list_ids).limit(20)

      # Format for JSON response
      results = lists.map do |list|
        current_entry = list.current_entry(current_user)
        {
          id: list.id,
          name: list.name,
          description: list.description,
          creator: list.user.username || list.user.email.split('@').first,
          entryCount: list.entries.count,
          isPrivate: list.private?,
          posterUrl: current_entry && current_entry.poster.attached? ? url_for(current_entry.poster) : (current_entry&.pic),
          canSubscribe: current_user && list.user_id != current_user.id && !current_user.subscribed_to?(list)
        }
      end

      render json: { lists: results }
    else
      render json: { lists: [] }
    end
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

    # The breadcrumb calls top_level?/parent_lists several times; load it once so those
    # are array operations rather than a fresh EXISTS/COUNT each time.
    @list.parent_lists.load

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
      return
    end

    if current_user
      # Use user-specific position
      current_entry = @list.current_entry(current_user)

      if current_entry
        redirect_to watch_entry_path(current_entry)
      else
        # No current entry set for this user - find appropriate starting point
        fallback_entry = if @list.ordered?
          # For ordered lists, find the first incomplete entry
          @list.find_next_incomplete_entry_for_user(current_user, 0)
        else
          # For unordered lists, find a random incomplete entry
          @list.find_random_incomplete_entry_for_user(current_user)
        end

        if fallback_entry
          # Update user's position
          user_position = @list.position_for_user!(current_user)
          user_position.update_to_entry!(fallback_entry)

          message = @list.ordered? ?
            "Starting from your next unwatched entry." :
            "Here's something you haven't watched yet!"
          redirect_to watch_entry_path(fallback_entry), notice: message
        else
          redirect_to list_path(@list), notice: "You've completed all entries in this list!"
        end
      end
    else
      # For guest users, just pick the first entry
      first_entry = @list.entries.order(:position).first
      redirect_to watch_entry_path(first_entry)
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
      Rails.logger.info "Fetching episode ##{counter + 1} data"
      omdb_result = OmdbApi.get_movie(episode[:imdb_id])
      next if omdb_result.nil?
      next if !!(omdb_result["Title"] =~ /\s[Pp]art\s/)
      omdb_result["seriesID"] = series_imdb_id
      omdb_result["imdbRating"] = episode[:rating]
      @entry = Entry.create_from_source(omdb_result, @list, false)
      next unless @entry.is_a?(Entry)
      # The scraper returns the episode's own title; fall back to it when OMDB gave us
      # no series name (`scraper_results` never existed and raised NameError here).
      @entry.update(series: episode[:title]) if @entry.series.nil?
      counter += 1
    end
    flash[:notice] = "#{ActionController::Base.helpers.pluralize(counter, 'episode')} of #{@list.entries.last&.series} added"
    redirect_to list_path(@list)
  end

  def add_season
    result = SeasonImporter.new(
      list: @list,
      tmdb_id: params[:tmdb],
      series_imdb_id: params[:series_imdb],
      series_name: params[:series_name],
      season: params[:season],
      media_type: params[:media_type]
    ).call

    case result[:status]
    when :created
      render json: {
        success: true,
        message: result[:message],
        entry_id: result[:entry].id,
        episodes_added: result[:episodes_added],
        episodes_failed: result[:episodes_failed]
      }
    when :duplicate
      render json: { error: result[:message] }, status: :unprocessable_entity
    else
      render json: { error: result[:message] }, status: :internal_server_error
    end
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
    favorites_list = current_user.lists.find_by(mobile: true)
    return render json: { error: 'Favorites list not found' }, status: :not_found unless favorites_list

    render_import(ImdbEntryImporter.new(list: favorites_list, imdb_id: params[:imdb], tmdb_id: params[:tmdb]).call)
  end

  def add_to_list
    list = current_user.lists.find_by(id: params[:list_id])
    return render json: { error: 'List not found' }, status: :not_found unless list

    unless current_user.can_edit_list?(list)
      return render json: { error: 'You do not have permission to add to this list' }, status: :forbidden
    end

    render_import(ImdbEntryImporter.new(list: list, imdb_id: params[:imdb], tmdb_id: params[:tmdb]).call)
  end

  # def watch_random
  #   watch_path(@list.find_entry_by_position(:random))
  # end

  private

  def render_import(result)
    case result[:status]
    when :created
      render json: { success: true, message: result[:message], entry_id: result[:entry].id }
    when :not_found
      render json: { error: result[:message] }, status: :not_found
    else
      render json: { error: result[:message] }, status: :internal_server_error
    end
  end

  # Everything a list card on the index renders: the owner, the entry count, and the
  # current user's stored position (read by List#current_entry).
  def with_card_data(scope)
    # A correlated subquery rather than COUNT over a join: the recently-watched scope
    # already inner-joins entries filtered to this user's completed rows, and a joined
    # COUNT there silently reports completed entries instead of the list's real size.
    scope.includes(:user, :user_list_positions)
         .select('lists.*, (SELECT COUNT(*) FROM entries WHERE entries.list_id = lists.id) AS entries_count')
  end

  def mobile_request?
    request.user_agent =~ /Mobile|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
  end

  def set_list
    @list = List.find(params[:id] || params[:list_id])
  end

  def load_entries
    # Every entry partial asks for this user's completion and review state, so preload it
    # rather than issuing a lookup per entry.
    @list_entries = if params[:query].present?
                      @list.entries.includes(:user_entries).search_by_input(params[:query])
                    else
                      @list.entries.includes(:user_entries)
                    end

    # Load child lists with their positions in this parent context
    @child_lists = @list.child_relationships.includes(child_list: :parent_lists).order(:position).map do |rel|
      child = rel.child_list
      child.define_singleton_method(:position) { rel.position }
      child
    end

    @entries = {}
    # `settings` is the list's remembered grouping; an explicit param wins over it.
    @criteria = params[:criteria].presence || @list.settings.presence || 'Position'
    # Anything outside this list would reach `public_send` in filter_entries.
    @criteria = 'Position' unless GROUPING_CRITERIA.include?(@criteria)
    filter_entries(@criteria)
    @entries = @entries.transform_keys { |key| key.nil? ? 'Other' : key }
    @sections = sort_sections(@entries.keys, params[:sort].present? || @list.sort.present?)

    return unless @list.user == current_user
    # Only persist an explicit choice. A plain visit carries no params, and writing them
    # blindly used to wipe the list's remembered grouping on every page view.
    return if params[:criteria].blank? && params[:sort].blank?

    @list.update(settings: params[:criteria], sort: params[:sort])
  end

  def filter_entries(criteria)
    case criteria
    # `genre` and `year` are nullable (hand-added entries, fanedits), so every branch here
    # has to tolerate blanks rather than 500 the whole list page.
    when 'Genre'
      genres = @list_entries.flat_map { |entry| entry.genre.to_s.split(',').map(&:strip) }.reject(&:empty?).uniq.sort
      genres.each do |genre|
        @entries[genre] = @list_entries.select { |entry| entry.genre.to_s.include?(genre) }
      end
      ungrouped = @list_entries.select { |entry| entry.genre.blank? }
      @entries['Other'] = ungrouped if ungrouped.any?
    when 'Year'
      (1900..Date.today.year).step(10) do |year|
        decade_entries = @list_entries.select { |entry| entry.year.present? && entry.year >= year && entry.year < year + 10 }
        @entries["#{year}s"] = decade_entries unless decade_entries.empty?
      end
    when 'Watched'
      @entries['Unwatched'] = @list_entries.reject { |entry| entry.completed_by?(current_user) }.sort_by { |entry| entry.position || 0 }
      @entries['Watched'] = @list_entries.select { |entry| entry.completed_by?(current_user) }.sort_by { |entry| entry.position || 0 }
    else
      # criteria is whitelisted in load_entries, so this only ever reaches an attribute
      # reader -- it used to `send` any params-supplied method name.
      @entries = @list_entries.group_by { |entry| entry.public_send(criteria.downcase) }
    end
  end

  # Section keys are a mix of strings ('Action', 'Other') and numbers (Rating, Length,
  # Year), which raises if you just call .sort on them. Numbers first, then strings.
  def sort_sections(keys, descending)
    sorted = keys.sort_by { |key| [key.is_a?(Numeric) ? 0 : 1, key.is_a?(Numeric) ? key : key.to_s] }
    descending ? sorted.reverse : sorted
  end

  def list_params
    permitted = [:name, :description, :ordered, :private, :sort, :parent_list_id, :reviewable, :provider_id, :auto_play, :auto_next]
    permitted << :default if current_user&.can_set_default?
    params.require(:list).permit(permitted)
  end

  def check_edit_permissions
    # Allow editing if user is authenticated and has permission, OR if list is default
    unless (current_user&.can_edit_list?(@list)) || @list.default?
      redirect_to lists_path, alert: 'You do not have permission to perform this action.'
    end
  end
end
