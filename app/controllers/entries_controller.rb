# frozen_string_literal: true

require 'open-uri'

class EntriesController < ApplicationController
  include ActionView::RecordIdentifier
  skip_before_action :verify_authenticity_token
  before_action :set_list, only: %i[new create top_entries]
  before_action :set_entry, only: %i[show edit update duplicate destroy watch complete reportlink shuffle_current decrement_current increment_current update_positions]

  def new
    @entry = Entry.new
    @ids = @list.entries.map {|entry| "#{entry.id}-#{entry.imdb}"}.join('/')
  end

  def show; end

  def create
    if params[:custom]
      @entry = Entry.new(entry_params)
      @entry.list = @list
      @entry.position = @list.entries.count + 1
      @entry.media = 'fanedit' if nil
      if @entry.save
        redirect_to list_path(@list)
        flash.now[:notice] = "#{@entry.name} successfully created"
      else
        flash.now[:notice] = "Something went wrong"
        render :new
      end
    else
      omdb_result = OmdbApi.get_movie(params[:imdb])
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
    if @entry.update(entry_params.merge(list: @entry.list, source: fix_external_sources(entry_params["source"])))
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
      if @entry.list.ordered
        @entry.complete(false)
        current = @entry.list.assign_current(:previous)
        redirect_to watch_entry_path(current)
      else
        # session[:previous_entry_positions] ||= []
        # previous_position = @entry.list.current || @entry.list.entries.map(&:position).sample
        # session[:previous_entry_positions] << previous_position
        # @entry.list.find_entry_by_position(session[:previous_entry_positions][-2])
        # redirect_to watch_entry_path(session[:previous_entry_id][-1])
        list_positions = @entry.list.entries.map(&:position) - [@entry.list.current]
        random_entry_position = list_positions.sample
        current = @entry.list.assign_current(random_entry_position)
        redirect_to watch_entry_path(current)
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
      if @entry.list.ordered
        @entry.complete(true)
        current = @entry.list.assign_current(:next)
        redirect_to watch_entry_path(current)
      else
        @entry.complete(true)
        list_positions = @entry.list.entries.map(&:position) - [@entry.list.current]
        random_entry_position = list_positions.sample
        current = @entry.list.assign_current(random_entry_position)
        redirect_to watch_entry_path(current)
      end
    end
  end

  def shuffle_current
    list_positions = @entry.list.entries.where.not(completed: true).map(&:position) - [@entry.list.current]
    random_entry_position = list_positions.sample
    current = @entry.list.assign_current(random_entry_position)
    redirect_to watch_entry_path(current)
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
    completed = @entry.complete(!@entry.completed)
    @entry.list.assign_current(completed ? :next : :current)
  end

  def reportlink
    @entry.update(stream: !@entry.stream)
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
        url.gsub("file", "embed")
      else
        return url
      end
    end

    def entry_params
      params.require(:entry).permit(
        :list_id,
        :position,
        :series,
        :note,
        :category,
        :name,
        :year,
        :pic,
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
        subentries_attributes: [:id, :name, :pic, :plot, :imdb, :season, :episode, :rating, :length, :completed, :source, :year, :_destroy]
      )
    end

end
