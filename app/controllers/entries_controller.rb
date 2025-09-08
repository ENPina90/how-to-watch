# frozen_string_literal: true

require 'open-uri'

class EntriesController < ApplicationController
  include ActionView::RecordIdentifier
  skip_before_action :verify_authenticity_token
  before_action :set_list, only: %i[new create]
  before_action :set_entry, only: %i[show edit update duplicate destroy watch complete review complete_without_review reportlink repair_image migrate_poster shuffle_current decrement_current increment_current]

  def new
    @entry = Entry.new
    @ids = @list.entries.map {|entry| "#{entry.id}-#{entry.imdb}"}.join('/')
  end

  def show; end

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
      @entry = Entry.create_from_source(omdb_result, @list, false)
      if @entry.is_a?(Entry)
        if @entry.media == 'series'
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
    @entry.subentries.build if @entry.media == 'series'
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
    entry_params.merge(list: @entry.list, source: fix_external_sources(entry_params["source"]))
    if @entry.update(entry_params)
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
    @entry.list.assign_current(@entry.position)
    render layout: 'special_layout'
  end

  def decrement_current
    if @entry.media == 'series'
      @entry.set_current(-1)
      if params[:mode] == 'watch'
        redirect_to watch_entry_path(@entry)
      else
        redirect_to list_path(@entry.list, anchor: @entry.imdb)
      end
    else
      # decrement_current should just move to the previous entry without changing completion
      if @entry.list.user == current_user
        current = @entry.list.assign_current(:previous, current_user)
        redirect_to watch_entry_path(current || @entry)
      else
        # If not the list owner, just stay on current entry
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
    if @entry.media == 'series'
      @entry.set_current(1)
      if params[:mode] == 'watch'
        redirect_to watch_entry_path(@entry)
      else
        redirect_to list_path(@entry.list, anchor: @entry.imdb)
      end
    else
      # increment_current should just move to the next entry without marking as completed
      if @entry.list.user == current_user
        current = @entry.list.assign_current(:next, current_user)
        redirect_to watch_entry_path(current || @entry)
      else
        # If not the list owner, just stay on current entry
        redirect_to watch_entry_path(@entry)
      end
    end
  end

  def shuffle_current
    # Get entries that are not completed by the current user
    incomplete_entries = @entry.list.entries.joins(:user_entries)
                                           .where(user_entries: { user: current_user, completed: false })

    # If no incomplete entries found, fall back to all entries
    if incomplete_entries.empty?
      incomplete_entries = @entry.list.entries
    end

    # Exclude current entry
    list_positions = incomplete_entries.where.not(id: @entry.id).pluck(:position)
    random_entry_position = list_positions.sample

    if random_entry_position && @entry.list.user == current_user
      current = @entry.list.assign_current(random_entry_position, current_user)
      redirect_to watch_entry_path(current)
    else
      redirect_to watch_entry_path(@entry)
    end
  end

  def update_position
    @entry = Entry.find(params[:id])
    new_position = params[:position].to_i
    list = @entry.list

    new_position = [new_position, 1].max
    new_position = [new_position, list.entries.count].min

    ActiveRecord::Base.transaction do
      shift_positions(@entry, new_position)

      @entry.update!(position: new_position)
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
      @entry.list.assign_current(:next, current_user) if @entry.list.user == current_user
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
    end
  end

  def review
    # Mark as completed first if not already completed
    @entry.mark_completed_by!(current_user) unless @entry.completed_by?(current_user)

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
    @entry.mark_completed_by!(current_user)

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

  private

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
      if @entry.list.user == current_user
        if @entry.list.ordered
          # For ordered lists, go to next incomplete entry
          next_entry = @entry.list.find_next_incomplete_entry(current_user)
          if next_entry
            @entry.list.update(current: next_entry.position)
            redirect_to watch_entry_path(next_entry)
          else
            # No more incomplete entries, stay on current
            redirect_to watch_entry_path(@entry)
          end
        else
          # For unordered lists, go to random incomplete entry
          incomplete_entries = @entry.list.entries.joins(:user_entries)
                                                 .where(user_entries: { user: current_user, completed: false })
                                                 .where.not(id: @entry.id)

          if incomplete_entries.any?
            random_entry = incomplete_entries.sample
            @entry.list.update(current: random_entry.position)
            redirect_to watch_entry_path(random_entry)
          else
            # No more incomplete entries, stay on current
            redirect_to watch_entry_path(@entry)
          end
        end
      else
        # If not list owner, just redirect to current entry
        redirect_to watch_entry_path(@entry)
      end
    end

end
