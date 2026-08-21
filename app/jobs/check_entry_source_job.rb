class CheckEntrySourceJob < ApplicationJob
  queue_as :default

  # The entry may have been deleted between enqueue and perform.
  discard_on ActiveJob::DeserializationError

  def perform(entry)
    entry.check_source
  rescue StandardError => e
    Rails.logger.error "Error checking source for Entry #{entry.id}: #{e.message}"
  end
end
