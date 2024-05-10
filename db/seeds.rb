require "faker"
require "csv"

# # Movie seeds
URL = "http://www.omdbapi.com/?"


# puts "Destroying all entries, lists, and users..."
# FailedEntry.destroy_all
# Entry.destroy_all
# List.destroy_all
# User.destroy_all

# # User seeds
User.create(email: "nic@gmail.com", password: "123456", username: "nic")
User.create(email: "idk@gmail.com", password: "123456", username: "idk")

CSV.foreach('db/seed_data/movie_list.csv', headers: :first_row, header_converters: :symbol) do |movie|
  puts "searching: #{movie[:title]} (#{movie[:year]})"
  entry = Entry.csv_to_movie(movie, User.first)
  if !entry && movie[:alt].present?
    movie[:title] = movie[:alt]
    entry = Entry.csv_to_movie(movie, User.first)
  end
  puts entry.class
  puts "-------------------------------------------------------------------------------------------"
end

Rake::Task['export:entries'].invoke
