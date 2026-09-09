# frozen_string_literal: true

# Turns a runtime audit into one notification per entry the schedule has to guess for.
#
# Reconciles rather than appends, as the poster and expiry notifiers do: a missing runtime
# is a state, not an event. Each run works out the set of warnings that should exist now,
# creates the ones missing, and deletes any `missing_runtime` row that is no longer earned
# -- runtime filled in, entry deleted, channel taken off the dial, or the row belonging to
# an account that is no longer an admin. So filling one in clears its notification without
# anyone dismissing it.
#
# That is also what makes dismissal safe here. The key carries only the entry, so dismissing
# hides it for good -- until the row is deleted by a later run, which is exactly what
# happens when the runtime arrives. Losing it again afterwards is a fresh notification.
class MissingRuntimeNotifier
  Result = Struct.new(:checked, :missing, :created, :removed, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(audit: MissingRuntimeAudit.new)
    @audit = audit
  end

  def call
    audit = @audit.call
    created = 0
    removed = 0

    # One transaction: a half-reconciled state would show warnings for runtimes that had
    # already been filled in.
    ActiveRecord::Base.transaction do
      admins.each do |admin|
        created += create_missing(admin, audit.missing)
        removed += remove_stale(admin, audit.missing)
      end

      removed += Notification.where(kind: Notification::MISSING_RUNTIME)
                             .where.not(user_id: admins.map(&:id))
                             .delete_all
    end

    Result.new(checked: audit.checked, missing: audit.missing.size, created: created, removed: removed)
  end

  private

  def admins = @admins ||= User.where(admin: true).to_a

  def key_for(row) = "#{Notification::MISSING_RUNTIME}:#{row.entry.id}"

  def create_missing(admin, rows)
    existing = admin_keys(admin)

    rows.count do |row|
      next false if existing.include?(key_for(row))

      Notification.create!(
        user: admin,
        kind: Notification::MISSING_RUNTIME,
        subject: row.entry,
        dedupe_key: key_for(row),
        # Denormalised so the card still reads correctly for an entry that has since been
        # deleted, and so the wording does not shift under a dismissed row.
        data: {
          'name' => row.entry.name,
          'list' => row.entry.list.name,
          'channel' => row.channel.name,
          'media' => row.entry.media,
          'guess' => CableSchedule.fallback_minutes(row.entry),
          # A show does not have a runtime, its episodes do -- so for a series the useful
          # thing to say is which of them are bare, not that the show itself is.
          'episodes' => row.entry.subentries.count,
          'episodes_missing' => row.entry.subentries.where(length: [nil, 0]).count
        }
      )
      true
    end
  end

  def remove_stale(admin, rows)
    Notification.where(user: admin, kind: Notification::MISSING_RUNTIME)
                .where.not(dedupe_key: rows.map { |row| key_for(row) })
                .delete_all
  end

  def admin_keys(admin)
    Notification.where(user: admin, kind: Notification::MISSING_RUNTIME).pluck(:dedupe_key).to_set
  end
end
