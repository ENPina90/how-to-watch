class Entry < ApplicationRecord
  belongs_to :list

  URL = "http://www.omdbapi.com/?"
  API = "&apikey=a881ace5"

  # def self.genres
  #   Entry.all.group_by(&:genre).keys.map(&:split).flatten.map { |genre| genre.tr(',', '') }.uniq.sort
  # end

  def self.get_imdb(title, number = 1, year = nil)
    omdb_search = "#{URL}s=#{title.strip}#{API}"
    serialized_search = URI.parse(URI::Parser.new.escape(omdb_search)).open.read
    response = JSON.parse(serialized_search)
    return nil if response["Error"]

    selection = year.nil? ? response["Search"].first(number) : response["Search"].select { |hash| hash["Year"] == year }
    selection.map { |movie| movie["imdbID"] }
  end

  def self.get_movie(imdb_id)
    omdb_url = "#{URL}i=#{imdb_id}#{API}"
    serialized_title = URI.parse(omdb_url).open.read
    result = JSON.parse(serialized_title)
    return nil if result["Type"] != "movie" || result["Poster"] == "N/A"

    return result
  end

  def self.create_movie(result)
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
      language: result["Language"],
      imdb: result["imdbID"],
      completed: false,
      note: "",
      review: ""
    )
  end
end
