class EntriesController < ApplicationController
  skip_before_action :verify_authenticity_token

  def new
    @list = List.find(params[:list_id])
    @entry = Entry.new
  end

  def create
    @entry = omdb_create
    raise
    redirect_to list_path(@entry.list)
  end

  private

  def omdb_create
    url = "http://www.omdbapi.com/?i=#{params["imdb"]}&apikey=a881ace5"
    serialized_title = URI.parse(url).open.read
    result = JSON.parse(serialized_title)
    # p result_title
    entry = Entry.create(
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
      list: params['list_id']
    )
    return entry
  end
end
