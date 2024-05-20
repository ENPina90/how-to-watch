FactoryBot.define do
  factory :entry do
    # Define the necessary attributes here
    name { "Example Entry" }
    list
    year { 2021 }
    imdb { "tt1234567" }
    completed { false }
    stream { false }
  end
end
