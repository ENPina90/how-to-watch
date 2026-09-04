web: rails assets:precompile && rails db:migrate && rails sources:seed_quietly && rails server -b 0.0.0.0 -p $PORT
worker: bundle exec sidekiq -C config/sidekiq.yml
