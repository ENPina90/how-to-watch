# frozen_string_literal: true

# Turns a poster audit into one notification per entry that will not render.
#
# Reconciles rather than appends, for the same reason SourceExpiryNotifier does: a broken
# poster is a *state*, not an event. Each run works out the set of warnings that should
# exist right now, creates the ones missing, and deletes any `broken_poster` row that is no
# longer earned -- poster replaced, entry deleted, or belonging to an account that is no
# longer an admin. So fixing a poster clears its notification without anyone dismissing it.
#
# The dedupe key carries the URL that was found broken, which is what makes dismissal safe:
# dismissing hides this entry until its poster URL changes, and changing the poster is
# exactly what fixing it does. A different URL is a new notification.
class BrokenPosterNotifier
  Result = Struct.new(:checked, :broken, :created, :removed, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(audit: PosterAudit.new)
    @audit = audit
  end

  def call
    audit = @audit.call
    created = 0
    removed = 0

    # One transaction: a half-reconciled state would show warnings for posters that had
    # already been replaced.
    ActiveRecord::Base.transaction do
      admins.each do |admin|
        created += create_missing(admin, audit.broken)
        removed += remove_stale(admin, audit.broken)
      end

      # Rows belonging to accounts that are no longer admins, or were deleted as admins
      # between runs. Handled outside the per-admin loop because those users are not in it.
      removed += Notification.where(kind: Notification::BROKEN_POSTER)
                             .where.not(user_id: admins.map(&:id))
                             .delete_all
    end

    Result.new(checked: audit.checked, broken: audit.broken.size, created: created, removed: removed)
  end

  private

  def admins = @admins ||= User.where(admin: true).to_a

  # Digested rather than carried whole: a pic column can hold a URL of any length, and the
  # key only has to change when the URL does.
  def key_for(row) = "#{Notification::BROKEN_POSTER}:#{row.entry.id}:#{Digest::SHA256.hexdigest(row.url.to_s)[0, 16]}"

  def create_missing(admin, rows)
    existing = admin_keys(admin)

    rows.count do |row|
      next false if existing.include?(key_for(row))

      Notification.create!(
        user: admin,
        kind: Notification::BROKEN_POSTER,
        subject: row.entry,
        dedupe_key: key_for(row),
        # Denormalised so the page can still describe a warning about an entry that has
        # since been deleted, and so the wording does not change under a dismissed row.
        data: {
          'name' => row.entry.name,
          'list' => row.entry.list.name,
          'source' => row.source,
          'reason' => row.reason,
          'url' => row.url.to_s.truncate(500)
        }
      )
      true
    end
  end

  def remove_stale(admin, rows)
    Notification.where(user: admin, kind: Notification::BROKEN_POSTER)
                .where.not(dedupe_key: rows.map { |row| key_for(row) })
                .delete_all
  end

  def admin_keys(admin)
    Notification.where(user: admin, kind: Notification::BROKEN_POSTER).pluck(:dedupe_key).to_set
  end
end
