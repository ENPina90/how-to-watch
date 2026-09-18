# frozen_string_literal: true

# What the admin warnings have in common.
#
# Each one is about a *state* -- a poster that will not load, a provider about to expire, an
# entry with no runtime -- rather than an event. So a run reconciles rather than appends:
# work out the set of warnings that should exist right now, create the ones missing, and
# delete any row of that kind no longer earned. Fixing the thing clears its notification
# without anyone dismissing it, which is the whole reason these are not just created once
# and left.
#
# A subclass says three things: the `kind` it writes, the `dedupe_key` for a row, and the
# subject and data a row becomes. Everything else is the same for all of them and lives
# here -- the transaction, the per-admin loop, and the sweep of rows belonging to accounts
# that are no longer admins.
#
# `call` stays with the subclass: each returns its own Result, and what a run counted
# (posters checked, entries audited) differs enough that a shared one would say less.
class AdminStateNotifier
  def self.call(...) = new(...).call

  private

  # The kind of notification this reconciles. `Notification::BROKEN_POSTER` and friends.
  def kind
    raise NotImplementedError, "#{self.class} must say which notification kind it writes"
  end

  # Stable for as long as the warning is the same warning, and different once it is not --
  # that is what makes dismissal safe, since a dismissed row stays hidden until the thing
  # it describes actually changes.
  def key_for(row)
    raise NotImplementedError, "#{self.class} must build a dedupe key for a row"
  end

  # The subject and data for one row. Denormalised into `data` so the page can still
  # describe a warning whose subject has since been deleted, and so the wording does not
  # change under a row somebody dismissed.
  def notification_for(row)
    raise NotImplementedError, "#{self.class} must turn a row into notification attributes"
  end

  # Reconcile every admin against `rows`. Returns [created, removed].
  def reconcile(rows)
    created = 0
    removed = 0

    # One transaction: a half-reconciled state would show warnings for things that had
    # already been put right.
    ActiveRecord::Base.transaction do
      admins.each do |admin|
        created += create_missing(admin, rows)
        removed += remove_stale(admin, rows)
      end

      # Rows belonging to accounts that are no longer admins, or that were deleted as
      # admins between runs. Handled outside the per-admin loop because those users are
      # not in it.
      removed += Notification.where(kind: kind)
                             .where.not(user_id: admins.map(&:id))
                             .delete_all
    end

    [created, removed]
  end

  def admins = @admins ||= User.where(admin: true).to_a

  def create_missing(admin, rows)
    existing = admin_keys(admin)

    rows.count do |row|
      next false if existing.include?(key_for(row))

      Notification.create!(notification_for(row).merge(user: admin, kind: kind, dedupe_key: key_for(row)))
      true
    end
  end

  def remove_stale(admin, rows)
    Notification.where(user: admin, kind: kind)
                .where.not(dedupe_key: rows.map { |row| key_for(row) })
                .delete_all
  end

  def admin_keys(admin)
    Notification.where(user: admin, kind: kind).pluck(:dedupe_key).to_set
  end
end
