require "faker"
require "csv"

# # Movie seeds
URL = "http://www.omdbapi.com/?"
# API = "&apikey=a881ace5"
# API = "&apikey=eb34d99"
API = "&apikey=b64b5a87"

# puts "Destroying all entries, lists, and users..."
# Entry.destroy_all
# List.destroy_all
# User.destroy_all

# # User seeds
# User.create(email: "nic@gmail.com", password: "123456", username: "nic")
# User.create(email: "idk@gmail.com", password: "123456", username: "idk")

# # Superhero List
# movies = ["batman", "superman", "spider man", "wonder woman", "thor", "black panther", "avengers"]
# list = List.create(name: "Superhero Movies", user: User.all.sample)
# movies.each do |movie|
#   movie_ids = Entry.get_imdb(movie, 3)
#   movie_ids.each do |imdb_id|
#     p omdb_result = Entry.get_movie(imdb_id)
#     entry = Entry.create_movie(omdb_result)
#     entry.list = list
#     entry.note = Faker::Lorem.paragraph
#     entry.category = movie
#     p entry.save
#   end
# end

# # Sci-Fi List
# movies = ['Star Wars', 'Star Trek', 'Alien', 'The Matrix']
# list = List.create(name: "Sci-Fi Movies", user: User.last)
# movies.each do |movie|
#   movie_ids = Entry.get_imdb(movie, 3)
#   movie_ids.each do |imdb_id|
#     p omdb_result = Entry.get_movie(imdb_id)
#     entry = Entry.create_movie(omdb_result)
#     entry.list = list
#     entry.note = Faker::Lorem.paragraph
#     entry.category = movie
#     p entry.save
#   end
# end

# # Best Movies List
# list = List.create name: "1000+ Movies to Watch Before You Die", user: User.first

def csv_to_entry(movie)
  p imdb_id = Entry.get_imdb(movie[:title], 1, movie[:year])
  p omdb_result = Entry.get_movie(imdb_id.first) unless imdb_id.nil?
  p Entry.create_movie(omdb_result) unless omdb_result.nil?
end


CSV.foreach('db/seed_data/movie_list.csv', headers: :first_row, header_converters: :symbol) do |movie|
  puts "searching: #{movie[:title]} #{movie[:year]}"
  next if Entry.find_by(name: movie[:title].strip, year: movie[:year], list: List.last)

  entry = csv_to_entry(movie)
  if entry.nil?
    movie[:title] = movie[:alt] if movie[:alt]
    next if Entry.find_by(name: movie[:title].strip, year: movie[:year], list: List.last)

    entry = csv_to_entry(movie)
    if entry.nil?
      puts "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      FailedEntry.create(name: movie[:title], alt: movie[:alt], year: movie[:year])
      next
    end
  else
    entry.list = List.last
    # entry.note = Faker::Lorem.paragraph
    entry.category = movie
    entry.completed = movie[:seen] == "TRUE"
    entry.stream = entry.check_source
  end
  p entry.save
end
