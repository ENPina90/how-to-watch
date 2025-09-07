class AttachPosterFromPicJob < ApplicationJob
  queue_as :default

  def perform(entry)
    return unless entry.pic.present? && !entry.poster.attached?

    Rails.logger.info "Attaching poster from pic URL for Entry #{entry.id}: #{entry.name}"

    # Use the existing PosterMigrationService
    service = PosterMigrationService.new
    result = service.migrate_entry_poster(entry)

    if result[:status] == 'migrated'
      Rails.logger.info "Successfully attached poster for Entry #{entry.id}: #{result[:message]}"
    else
      Rails.logger.warn "Failed to attach poster for Entry #{entry.id}: #{result[:message]}"
    end

  rescue StandardError => e
    Rails.logger.error "Error attaching poster for Entry #{entry.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end

