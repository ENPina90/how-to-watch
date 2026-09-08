# frozen_string_literal: true

# Finds the entries that frame up and say "This media is unavailable", marks them, and
# tells the admins.
#
# Nobody here causes this and nobody here can see it coming: VidSrc's catalogue changes
# under the app, so an entry that played last week may have nothing behind it this week --
# and the embed still answers 200, so nothing surfaces it. That needs somebody to go and
# ask, and this is that somebody.
#
# Weekly, and a day after the poster scan rather than alongside it, so two sweeps are not
# making outbound requests at the same time.
class EmbedAvailabilityScanJob < ApplicationJob
  queue_as :default

  def perform
    audit = EmbedAvailabilityAudit.call
    marked = mark_broken(audit.missing)
    notified = UnplayableEmbedNotifier.call(missing: audit.missing)

    Rails.logger.info(
      "Embed availability scan: #{audit.missing.size} of #{audit.checked} entries unplayable, " \
      "#{marked} newly marked broken, #{notified.created} notification(s) raised, #{notified.removed} retired"
    )
  rescue EmbedAvailabilityAudit::CannotCheck => e
    # Not worth retrying into: it means VidSrc itself is not answering, and the next run is
    # a week of provider weather away from this one.
    Rails.logger.warn("Embed availability scan skipped: #{e.message}")
  end

  private

  # The same mark the "report broken link" button leaves, so an unplayable entry wears the
  # red link on its card without anyone having pressed anything.
  #
  # One direction only. Clearing the mark when VidSrc picks a title back up would also
  # clear it from every entry somebody reported by hand for a reason this job cannot see --
  # a dead Drive link, the wrong cut, no subtitles. The notification is what retires on its
  # own; the mark is left for a person to take off.
  def mark_broken(rows)
    ids = rows.map { |row| row.entry.id }
    return 0 if ids.empty?

    Entry.where(id: ids).where(stream: [true, nil]).update_all(stream: false, updated_at: Time.current)
  end
end
