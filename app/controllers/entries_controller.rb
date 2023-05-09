require 'open-uri'

class EntriesController < ApplicationController
  skip_before_action :verify_authenticity_token

  def new
    @list = List.find(params[:list_id])
    @entry = Entry.new
  end

  def create
    @entry = omdb_create(params[:imdb])
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

  def omdb_create(imdb_id)
    url = "http://www.omdbapi.com/?i=#{imdb_id}&apikey=a881ace5"
    serialized_title = URI.parse(url).open.read
    result = JSON.parse(serialized_title)
    Entry.create(
      media: 'Movie',
      name: result["Title"],
      year: result["Year"].to_i,
      pic: result["Poster"],
      genre: result["Genre"],
      director: result["Director"],
      writer: result["Writer"],
      actors: result["Actors"],
      plot: result["Plot"],
      rating: result["imdbRating"].to_f,
      length: result["Runtime"].split(" ")[0].to_i,
      list: List.find(params['list_id']),
      language: result["Language"],
      imdb: result["imdbID"]
    )
  end

  private

  def entry_params
    params.require(:entry).permit(:note, :category, :name, :year, :pic, :genre, :director, :writer, :actors, :plot, :rating, :length, :list_id)
  end
end
