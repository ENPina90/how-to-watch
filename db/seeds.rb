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
require "csv"

# # Movie seeds
URL = "http://www.omdbapi.com/?"
API = "&apikey=eb34d99"

puts "Destroying all entries, lists, and users..."
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

# # User seeds
User.create(email: "nic@gmail.com", password: "123456")
User.create(email: "idk@gmail.com", password: "123456")

def create_movie(entry)
  Entry.create(
    media: 'Movie',
    name: entry["Title"],
    year: entry["Year"].to_i,
    pic: entry["Poster"],
    genre: entry["Genre"],
    director: entry["Director"],
    writer: entry["Writer"],
    actors: entry["Actors"],
    plot: entry["Plot"],
    rating: entry["imdbRating"].to_f,
    length: entry["Runtime"].split(" ")[0].to_i,
    imdb: entry["imdbID"],
    language: entry["Language"],
    completed: entry["seen"],
    list: List.last
  )
end

def get_movie(movie)
  p omdb_search = "#{URL}s=#{movie[:title].strip}#{API}"
  serialized_search = URI.parse(URI::Parser.new.escape(omdb_search)).open.read
  p response = JSON.parse(serialized_search)
  return nil if response["Error"]

  result = response["Search"].select { |hash| hash["Year"] == movie[:year] }
  return nil if result.empty?

  omdb_title = "#{URL}i=#{result.first["imdbID"]}#{API}"
  serialized_title = URI.parse(omdb_title).open.read
  result = JSON.parse(serialized_title)
  return nil if result["Type"] != "movie" || result["Poster"] == "N/A"

  return result
end


List.create(name: "Superhero Movies", user: User.last)
movies.each do |movie|
  # List seeds
  omdb_search = "#{URL}s=#{movie}#{API}"

  serialized_search = URI.parse(omdb_search).open.read
  results = JSON.parse(serialized_search)["Search"]

  results.first(5).each do |result|
    next if result["Type"] != "movie" || result["Poster"] == "N/A" || result.nil?

    omdb_title = "#{URL}i=#{result["imdbID"]}#{API}"
    serialized_title = URI.parse(omdb_title).open.read
    result = JSON.parse(serialized_title)
    result["seen"] = [true, false].sample
    # p result_title
    entry = create_movie(result)
    entry.update(note: Faker::Lorem.paragraph(sentence_count: 2))
    p entry
  end
end


skipped = []
List.create name: "1000+ Movies to Watch Before You Die", user: User.first

CSV.foreach('db/seed_data/movie_list.csv', headers: :first_row, header_converters: :symbol) do |movie|
  puts "searching for #{movie[:title]} #{movie[:year]}"
  entry = get_movie(movie)

  if entry.nil?
    movie[:title] = movie[:alt] if movie[:alt]
    entry = get_movie(movie)
    next if entry.nil?
  end
  entry = create_movie(entry)
  entry.update(completed: movie[:seen] == "TRUE")
  p entry
end
p skipped
