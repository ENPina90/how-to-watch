require 'open-uri'

class EntriesController < ApplicationController
  skip_before_action :verify_authenticity_token

  def new
    @list = List.find(params[:list_id])
    @entry = Entry.new
  end

  def create
    @list = List.find(params[:list_id])
    omdb_result = Entry.get_movie(params[:imdb])
    @entry = Entry.create_movie(omdb_result)
    @entry.list = @list
    @entry.save
    redirect_to edit_entry_path(@entry)
  end

  def edit
    @entry = Entry.find(params[:id])
  end

  def update
    @entry = Entry.find(params[:id])
    @entry.update(entry_params)
    redirect_to list_path(@entry.list)
  end

  def watch
    @entry = Entry.find(params[:id])
    render layout: "special_layout"
  end

  def complete
    @entry = Entry.find(params[:id])
    @entry.update(completed: true)
    raise
  end

  private

  def entry_params
    params.require(:entry).permit(:note, :category, :name, :year, :pic, :genre, :director, :writer, :actors, :plot, :rating, :length, :list_id, :media, :source, :imdb, :language, :review)
  end
end
