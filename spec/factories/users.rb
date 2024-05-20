FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    password { "password" }
    # Add other necessary attributes and associations
  end
end
