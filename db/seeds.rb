require "faker"
require "csv"

# # Movie seeds
URL = "http://www.omdbapi.com/?"
API = "&apikey=a881ace5"
# API = "&apikey=eb34d99"
SKIPPED = []

puts "Destroying all entries, lists, and users..."
Entry.destroy_all
List.destroy_all
User.destroy_all

User seeds
User.create(email: "nic@gmail.com", password: "123456", username: "nic")
User.create(email: "idk@gmail.com", password: "123456", username: "idk")

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


# Best Movies List
def csv_to_entry(movie)
  imdb_id = Entry.get_imdb(movie[:title], 1, movie[:year])
  p omdb_result = Entry.get_movie(imdb_id)
  Entry.create_movie(omdb_result)
end

list = List.create name: "1000+ Movies to Watch Before You Die", user: User.first

CSV.foreach('db/seed_data/movie_list.csv', headers: :first_row, header_converters: :symbol) do |movie|
  puts "searching for #{movie[:title]} #{movie[:year]}"

  entry = csv_to_entry(movie)
  if entry.nil?
    movie[:title] = movie[:alt] if movie[:alt]
    entry = csv_to_entry(movie)
    if entry.nil?
      SKIPPED << movie
      next
    end
  else
    entry.list = list
    entry.note = Faker::Lorem.paragraph
    entry.category = movie
    entry.completed = movie[:seen] == "TRUE"
  end
  p entry.save
end
p SKIPPED
