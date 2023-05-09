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
API = "&apikey=a881ace5"
# API = "&apikey=eb34d99"

# puts "Destroying all entries, lists, and users..."
# Entry.destroy_all
# List.destroy_all
# User.destroy_all

# User seeds
User.create(email: "nic@gmail.com", password: "123456")
User.create(email: "idk@gmail.com", password: "123456")

# Superhero List
movies = ["batman", "superman", "spiderman", "wonder woman", "thor", "black panther", "avengers"]
list = List.create(name: "Superhero Movies", user: User.sample)
movies.each do |movie|
  movie_ids = Entry.get_imdb(movie, 3)
  movie_ids.each do |imdb_id|
    p omdb_result = Entry.get_movie(imdb_id)
    entry = Entry.create_movie(omdb_result)
    entry.list = list
    entry.note = Faker::Lorem.paragraph
    entry.category = movie
    p entry.save
  end
end

# Sci-Fi List
movies = ['Star Wars', 'Star Trek', 'Alien', 'The Matrix']
list = List.create(name: "Sci-Fi Movies", user: User.last)
movies.each do |movie|
  movie_ids = Entry.get_imdb(movie, 3)
  movie_ids.each do |imdb_id|
    p omdb_result = Entry.get_movie(imdb_id)
    entry = Entry.create_movie(omdb_result)
    entry.list = list
    entry.note = Faker::Lorem.paragraph
    entry.category = movie
    p entry.save
  end
end

def csv_to_entry(movie)
  imdb_id = Entry.get_imdb(movie[:title], 1, movie[:year])
  p omdb_result = Entry.get_movie(imdb_id)
  Entry.create_movie(omdb_result)
end

# Best Movies List
list = List.create name: "1000+ Movies to Watch Before You Die", user: User.first

CSV.foreach('db/seed_data/movie_list.csv', headers: :first_row, header_converters: :symbol) do |movie|
  puts "searching for #{movie[:title]} #{movie[:year]}"

  entry = csv_to_entry(movie)
  if entry.nil?
    movie[:title] = movie[:alt] if movie[:alt]
    entry = csv_to_entry(movie)
    next if entry.nil?
  else
    entry.list = list
    entry.note = Faker::Lorem.paragraph
    entry.category = movie
    entry.completed = movie[:seen] == "TRUE"
  end
  p entry.save
end

# def create_movie(entry)
#   Entry.create(
#     media: 'Movie',
#     name: entry["Title"],
#     year: entry["Year"].to_i,
#     pic: entry["Poster"],
#     genre: entry["Genre"],
#     director: entry["Director"],
#     writer: entry["Writer"],
#     actors: entry["Actors"],
#     plot: entry["Plot"],
#     rating: entry["imdbRating"].to_f,
#     length: entry["Runtime"].split(" ")[0].to_i,
#     imdb: entry["imdbID"],
#     language: entry["Language"],
#     completed: entry["seen"],
#     list: List.last
#   )
# end

# def get_movie(movie)
#   p omdb_search = "#{URL}s=#{movie[:title].strip}#{API}"
#   serialized_search = URI.parse(URI::Parser.new.escape(omdb_search)).open.read
#   p response = JSON.parse(serialized_search)
#   return nil if response["Error"]

#   result = response["Search"].select { |hash| hash["Year"] == movie[:year] }
#   return nil if result.empty?

#   omdb_title = "#{URL}i=#{result.first["imdbID"]}#{API}"
#   serialized_title = URI.parse(omdb_title).open.read
#   result = JSON.parse(serialized_title)
#   return nil if result["Type"] != "movie" || result["Poster"] == "N/A"

#   return result
# end

# ## Superhero Movies
# # List.create(name: "Superhero Movies", user: User.last)
# # movies.each do |movie|
# #   # List seeds
# #   omdb_search = "#{URL}s=#{movie}#{API}"

# #   serialized_search = URI.parse(omdb_search).open.read
# #   results = JSON.parse(serialized_search)["Search"]

# #   results.first(5).each do |result|
# #     next if result["Type"] != "movie" || result["Poster"] == "N/A" || result.nil?

# #     omdb_title = "#{URL}i=#{result["imdbID"]}#{API}"
# #     serialized_title = URI.parse(omdb_title).open.read
# #     result = JSON.parse(serialized_title)
# #     result["seen"] = [true, false].sample
# #     # p result_title
# #     entry = create_movie(result)
# #     entry.update(note: Faker::Lorem.paragraph(sentence_count: 2))
# #     p entry
# #   end
# # end

# # skipped = []

# p skipped
