# frozen_string_literal: true

require 'sidekiq/api'

# What commit each process is running, and whether a worker is alive to run anything.
#
# The web app and the Sidekiq worker are separate Railway services with their own deploy
# triggers, so they can drift apart -- and did, silently, for a day. The web build had a
# job class the worker's build did not, so every enqueue failed with UnknownJobClassError
# and nothing on the site said so; the only trace was in the Sidekiq retries tab. This is
# what makes that visible from the dashboard instead.
#
# Every Redis read is optional: development and test have no Redis, and a dashboard is not
# worth a 500 when the queue is down -- being down is precisely what it is here to show.
class DeploymentStatus
  KEY = 'howtowatch:worker-deployment'

  # A worker heartbeats every few seconds. Well past that and it is gone, not just busy.
  STALE_AFTER = 2.minutes

  # Written by the worker at boot, so it is evidence that this build actually started --
  # not merely that something was deployed.
  def self.record_worker!
    payload = { sha: current_sha, booted_at: Time.current.iso8601 }.to_json
    Sidekiq.redis { |redis| redis.set(KEY, payload) }
  rescue StandardError => e
    Sidekiq.logger.warn("Could not record the worker's deployment: #{e.class}: #{e.message}")
  end

  # Railway injects this on every deploy that came from a GitHub trigger. Absent locally,
  # and absent on a service deployed by hand from the CLI -- which is itself worth seeing,
  # because such a service never auto-deploys again.
  def self.current_sha
    ENV['RAILWAY_GIT_COMMIT_SHA'].presence
  end

  def web_sha = self.class.current_sha

  def worker_sha = recorded[:sha]

  def worker_booted_at
    Time.zone.parse(recorded[:booted_at].to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Sidekiq's own process registry, which is the authority on whether a worker is running
  # right now. The recorded boot above says what was deployed; this says what is alive.
  def live_processes
    @live_processes ||= Sidekiq::ProcessSet.new.to_a
  rescue StandardError
    []
  end

  def worker_running? = live_processes.any?

  def last_heartbeat
    beats = live_processes.filter_map { |process| process['beat'] }
    Time.zone.at(beats.max) if beats.any?
  end

  def stale? = last_heartbeat.nil? || last_heartbeat < STALE_AFTER.ago

  # Both sides known and different. An unknown sha is not drift, it is no information --
  # saying "mismatch" there would cry wolf on every local run.
  def drift?
    web_sha.present? && worker_sha.present? && web_sha != worker_sha
  end

  # Nothing useful to report, rather than a clean bill of health.
  def unknown? = web_sha.blank? && worker_sha.blank?

  def short(sha) = sha.presence&.first(7)

  private

  def recorded
    @recorded ||= begin
      raw = Sidekiq.redis { |redis| redis.get(KEY) }
      raw ? JSON.parse(raw).symbolize_keys : {}
    rescue StandardError
      {}
    end
  end
end
