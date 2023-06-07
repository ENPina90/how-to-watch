require "open-uri"

class Entry < ApplicationRecord
  belongs_to :list
  # validate :streamable

  URL = "http://www.omdbapi.com/?"
  API = ["&apikey=b64b5a87", "&apikey=eb34d99", "&apikey=a881ace5"]

  include PgSearch::Model
  pg_search_scope :search_by_input,
                  against: %i[name franchise category writer actors genre director],
                  using: {
                    tsearch: {
                      prefix: true
                    }
                  }

  # def self.genres
  #   Entry.all.group_by(&:genre).keys.map(&:split).flatten.map { |genre| genre.tr(',', '') }.uniq.sort
  # end

  def self.get_imdb(title, number = 1, year = nil)
    omdb_search = "#{URL}s=#{title.strip}#{API[0]}"
    serialized_search = URI.parse(URI::Parser.new.escape(omdb_search)).open.read
    response = JSON.parse(serialized_search)
    return nil if response["Error"]

    if year.nil?
      selection = response["Search"].first(number)
    else
      selection = response["Search"].select { |hash| ((year.to_i - 1)..(year.to_i + 1)).include?(hash["Year"].to_i) }
    end
    selection.map { |movie| movie["imdbID"] }
  end

  def self.get_movie(imdb_id)
    omdb_url = "#{URL}i=#{imdb_id}#{API[0]}"
    serialized_title = URI.parse(omdb_url).open.read
    result = JSON.parse(serialized_title)
    return nil if result["Error"] || result["Poster"] == "N/A"

    # return nil if result["Type"] != "movie" || result["Poster"] == "N/A"
    return result
  end

  def self.create_movie(result)
    Entry.new(
      media: result["Type"],
      source: "https://v2.vidsrc.me/embed/#{result["imdbID"]}",
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
      completed: false
    )
  end

  def check_source
    url = source
    begin
      URI.open(url).read
    rescue OpenURI::HTTPError
      return false
    end
    return true
  end

  def streamable
    unless stream
      update(source: '')
      errors.add(:source, "is unavailable, do you have an alternative?")
    end
  end
end
