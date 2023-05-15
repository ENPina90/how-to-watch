require 'open-uri'

class EntriesController < ApplicationController
  skip_before_action :verify_authenticity_token

  def new
    @entry = Entry.new
    @list = List.find(params[:list_id])
  end

  def create
    @list = List.find(params[:list_id])
    omdb_result = Entry.get_movie(params[:imdb])
    @entry = Entry.create_movie(omdb_result)
    @entry.franchise = Entry.get_movie(omdb_result['seriesID'])['Title']
    @entry.category = @entry.franchise
    @entry.list = @list
    @entry.stream = @entry.check_source
    @entry.save
    redirect_to edit_entry_path(@entry)
  end

  def edit
    @entry = Entry.find(params[:id])
    @entry.streamable
  end

  def update
    @entry = Entry.find(params[:id])
    params = entry_params
    @list = List.find(params['list'].to_i)
    params['list'] = @list
    @entry.update(params)
    redirect_to list_path(@list)
  end

  def duplicate
    @entry = Entry.find(params[:id])
    new_entry = @entry.dup
    new_entry.list = current_user.lists.first
    new_entry.save
    @entry = new_entry
    redirect_to edit_entry_path(@entry)
  end

  def destroy
    @entry = Entry.find(params[:id])
    @list = @entry.list
    @entry.destroy
    redirect_to list_path(@list), status: :see_other
  end

  def watch
    @entry = Entry.find(params[:id])
    render layout: "special_layout"
  end

  def complete
    @entry = Entry.find(params[:id])
    @entry.update(completed: !@entry.completed)
  end

  def reportlink
    @entry = Entry.find(params[:id])
    @entry.update(stream: !@entry.stream)
  end

  private

  def entry_params
    params.require(:entry).permit(:list, :note, :category, :name, :year, :pic, :genre, :director, :writer, :actors, :plot, :rating, :length, :media, :source, :imdb, :language, :review)
  end
end
