FactoryBot.define do
  factory :entry do
    position { 1 }
    franchise { "Marvel" }
    media { "movie" }
    imdb { "tt0848228" }
    season { nil }
    episode { nil }
    name { "The Avengers" }
    category { "Action, Adventure, Sci-Fi" }
    length { 143 }
    year { 2012 }
    plot { "Earth's mightiest heroes must come together and learn to fight as a team..." }
    pic { "https://example.com/poster.jpg" }
    genre { "Action, Adventure, Sci-Fi" }
    director { "Joss Whedon" }
    writer { "Joss Whedon" }
    actors { "Robert Downey Jr., Chris Evans, Scarlett Johansson" }
    rating { 8.0 }
    language { "English" }
    note { "Some note" }
    completed { false }
    association :list
  end
end
