# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)
# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)
require "faker"

Entry.destroy_all
List.destroy_all
User.destroy_all

movies = [
  "batman",
  "superman",
  "spiderman",
  "wonder woman",
  "thor",
  "black panther",
  "avengers"
]

# User seeds
User.create(email: "nic@gmail.com", password: "123456")
User.create(email: "idk@gmail.com", password: "123456")


# Movie seeds
URL = "http://www.omdbapi.com/?"
API = "&apikey=a881ace5"
master_list = List.create(name: "Superhero Movies", user: User.all.sample)

movies.each do |movie|
  # List seeds
  list = List.create(name: movie, user: User.all.sample)
  omdb_search = "#{URL}s=#{movie}#{API}"

  serialized_search = URI.parse(omdb_search).open.read
  results = JSON.parse(serialized_search)["Search"]

  results.first(5).each do |result|
    next if result["Type"] != "movie" || result["Poster"] == "N/A"

    omdb_title = "#{URL}i=#{result["imdbID"]}#{API}"
    serialized_title = URI.parse(omdb_title).open.read
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
      list: list,
      note: Faker::Markdown.emphasis
    )
    p entry
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
      list: master_list,
      note: Faker::Markdown.emphasis
    )
    # ListEntry.create(entry: entry, list: list)
    # ListEntry.create(entry: entry, list: master_list, category: movie, note: Faker::Markdown.emphasis)
  end
end
