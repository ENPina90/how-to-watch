namespace :sources do
  desc "Seed/refresh streaming provider definitions (idempotent)"
  task seed: :environment do
    load Rails.root.join("db/seeds/sources.rb")
  end
end
