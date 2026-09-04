# frozen_string_literal: true

# Keeps every admin's expiry warnings in step with what the sources actually say.
#
# This reconciles rather than appends, which is what makes a warning about a *state* behave
# sensibly as a notification. Each run works out the set of warnings that should exist right
# now, creates the ones missing, and deletes any `source_expiring` row that is no longer
# earned -- renewed, deactivated, made imperishable, or belonging to an account that is no
# longer an admin. So renewing a provider clears its warning without anyone dismissing it,
# and a dismissed warning cannot come back to life for the same date.
#
# Safe to run as often as you like: with nothing to do it writes nothing.
class SourceExpiryNotifier
  Result = Struct.new(:created, :removed, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(now: Date.current)
    @now = now
  end

  def call
    created = 0
    removed = 0

    # One transaction: a half-reconciled state would show warnings for dates that had
    # already been renewed past.
    ActiveRecord::Base.transaction do
      admins.each do |admin|
        created += create_missing(admin)
        removed += remove_stale(admin)
      end

      # Rows belonging to accounts that are no longer admins, or were deleted as admins
      # between runs. Handled outside the per-admin loop because those users are not in it.
      removed += Notification.where(kind: Notification::SOURCE_EXPIRING)
                             .where.not(user_id: admins.map(&:id))
                             .delete_all
    end

    Result.new(created: created, removed: removed)
  end

  private

  attr_reader :now

  def admins = @admins ||= User.where(admin: true).to_a

  # Expired sources are included, not just soon-to-expire: a provider that lapsed while
  # nobody was looking is the case this exists for.
  #
  # Deactivated ones are not. Nothing plays through them, so their address lapsing is not a
  # problem to be warned about -- which also makes "deactivate" a legitimate way to answer a
  # warning about a provider you have finished with.
  def due_sources
    @due_sources ||= Source.active.expiring_by(now + Source::EXPIRY_WARNING_WINDOW).to_a
  end

  # Carries the date so that renewing retires the warning rather than editing it -- a new
  # date is a new notification, and the dismissal of the old one does not silence it.
  def key_for(source) = "#{Notification::SOURCE_EXPIRING}:#{source.id}:#{source.valid_until}"

  def create_missing(admin)
    existing = admin_keys(admin)

    due_sources.count do |source|
      next false if existing.include?(key_for(source))

      Notification.create!(
        user: admin,
        kind: Notification::SOURCE_EXPIRING,
        subject: source,
        dedupe_key: key_for(source),
        # Denormalised so the page can render a warning about a source that has since been
        # deleted, and so the wording does not silently change under a dismissed row.
        data: { 'name' => source.name, 'slug' => source.slug, 'valid_until' => source.valid_until.to_s }
      )
      true
    end
  end

  def remove_stale(admin)
    Notification.where(user: admin, kind: Notification::SOURCE_EXPIRING)
                .where.not(dedupe_key: due_sources.map { |s| key_for(s) })
                .delete_all
  end

  def admin_keys(admin)
    Notification.where(user: admin, kind: Notification::SOURCE_EXPIRING).pluck(:dedupe_key).to_set
  end
end
