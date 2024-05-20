FactoryBot.define do
  factory :list do
    # Define the necessary attributes here
    name { "Example List" }
    user { create(:user) } # Assuming a user factory is defined
  end
end
