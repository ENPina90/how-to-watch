# frozen_string_literal: true

# Sidekiq shares the Redis instance Action Cable points at. REDIS_URL is set in production
# (Railway wires it from the Redis service); when it is missing Sidekiq falls back to its
# own localhost default, which is what a developer running `redis-server` locally expects.
#
# Development and test do not use this adapter at all -- development stays on :async and
# test on :test -- so a machine with no Redis is unaffected.
if ENV["REDIS_URL"].present?
  redis_config = { url: ENV["REDIS_URL"] }

  Sidekiq.configure_server { |config| config.redis = redis_config }
  Sidekiq.configure_client { |config| config.redis = redis_config }
end

# Periodic jobs live in config/schedule.yml. Loaded on the server only -- a web process
# registering them too would have several dynos racing to own the same schedule.
Sidekiq.configure_server do |config|
  config.on(:startup) do
    # Written by the worker itself, so the dashboard can show which build is actually
    # running here rather than which one was last deployed. See DeploymentStatus.
    DeploymentStatus.record_worker!

    schedule = Rails.root.join("config/schedule.yml")
    next unless schedule.exist?

    begin
      Sidekiq::Cron::Job.load_from_hash!(YAML.load_file(schedule))
    rescue StandardError => e
      # Registering the schedule touches Redis, and a failure here would otherwise take
      # the whole worker down at boot. Processing queued jobs matters more than the weekly
      # refresh, which the next restart will register anyway.
      Sidekiq.logger.error("Could not load config/schedule.yml: #{e.class}: #{e.message}")
    end
  end
end
