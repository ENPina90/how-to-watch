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
