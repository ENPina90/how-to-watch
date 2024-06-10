# frozen_string_literal: true

require 'open-uri'

class EntriesController < ApplicationController

  skip_before_action :verify_authenticity_token
  before_action :set_list, only: %i[new create]
  before_action :set_entry, only: %i[show edit update duplicate destroy watch complete reportlink decrement_current increment_current]

  def new
    @entry = Entry.new
  end

  def show; end

  def create
    omdb_result = OmdbApi.get_movie(params[:imdb])
    @entry = Entry.create_from_source(omdb_result, @list, false)
    if @entry.is_a?(Entry)
      # redirect_to edit_entry_path(@entry)
      # TODO make this render an edit form partial
      flash[:notice] = "#{@entry.name} added to #{@list.name}"
      render turbo_stream: turbo_stream.replace('flash', partial: 'shared/flashes')
    else
      flash.now[:alert] = 'theres a problem'
      render turbo_stream: turbo_stream.replace('flash', partial: 'shared/flashes')
    end
    begin
      if @entry.media == 'series'
        OmdbApi.get_series_episodes(@entry)
      end
    rescue
      flash[:error] = "This already exists in your list"
      # render :new
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
    list = List.find(entry_params[:list].to_i)
    if @entry.update(entry_params.merge(list: list))
      redirect_to list_path(@entry.list, anchor: @entry.imdb)
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
    list = @entry.list
    @entry.destroy
    redirect_to list_path(list), status: :see_other
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
        @entry.toggle_complete
        current = @entry.list.assign_current(:next)
        redirect_to watch_entry_path(current)
      else
        list_positions = @entry.list.entries.map(&:position) - [@entry.list.current]
        random_entry_position = list_positions.sample
        current = @entry.list.assign_current(random_entry_position)
        redirect_to watch_entry_path(current)
      end
    end
  end

  def complete
    completed = @entry.toggle_complete
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

    def entry_params
      params.require(:entry).permit(
        :list,
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
        :language,
        :review,
        subentries_attributes: [:id, :name, :pic, :plot, :imdb, :season, :episode, :rating, :length, :completed, :source, :year, :_destroy]
      )
    end

end
