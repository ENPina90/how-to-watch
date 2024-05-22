FactoryBot.define do
  factory :entry do
    position { 1 }
    franchise { "Marvel" }
    media { "movie" }
    season { nil }
    episode { nil }
    name { "Avengers" }
    category { "Action" }
    length { 120 }
    year { 2012 }
    plot { "Earth's mightiest heroes must come together..." }
    pic { "some_url" }
    source { "https://v2.vidsrc.me/embed/tt0848228" }
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
