class CheckEntrySourceJob < ApplicationJob
  queue_as :default

  def perform(entry)
    entry.check_source
  rescue StandardError => e
    Rails.logger.error "Error checking source for Entry #{entry.id}: #{e.message}"
  end
end
