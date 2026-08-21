class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Jobs now outlive the process that enqueued them, so the gap between enqueue and
  # perform can span a deploy. An entry deleted in that window would otherwise fail the
  # job (and burn Sidekiq's full retry schedule) over a record that is simply gone.
  discard_on ActiveJob::DeserializationError
end
