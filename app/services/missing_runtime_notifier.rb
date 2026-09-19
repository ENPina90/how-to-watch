# frozen_string_literal: true

# Turns a runtime audit into one notification per entry with no runtime recorded.
#
# Reconciles rather than appends, as the poster and expiry notifiers do: a missing runtime
# is a state, not an event. Each run works out the set of warnings that should exist now,
# creates the ones missing, and deletes any `missing_runtime` row that is no longer earned
# -- runtime filled in, entry deleted, or the row belonging to an account that is no longer
# an admin. So filling one in clears its notification without anyone dismissing it.
#
# A channel coming off the dial is not one of those reasons any more: the sweep covers the
# whole catalogue, so the entry is still bare and the warning still stands. What it does
# leave behind is the channel name in `data`, which is written once and not revisited -- the
# card goes on naming a channel that has stopped scheduling it until the runtime is filled
# in and the row retires. Saying "on Annals" a week late is a smaller fault than a card
# whose wording shifts under a dismissed row.
#
# That is also what makes dismissal safe here. The key carries only the entry, so dismissing
# hides it for good -- until the row is deleted by a later run, which is exactly what
# happens when the runtime arrives. Losing it again afterwards is a fresh notification.
class MissingRuntimeNotifier < AdminStateNotifier
  Result = Struct.new(:checked, :missing, :created, :removed, keyword_init: true)

  def initialize(audit: MissingRuntimeAudit.new)
    @audit = audit
  end

  def call
    audit = @audit.call
    created, removed = reconcile(audit.missing)

    Result.new(checked: audit.checked, missing: audit.missing.size, created: created, removed: removed)
  end

  private

  def kind = Notification::MISSING_RUNTIME

  def key_for(row) = "#{kind}:#{row.entry.id}"

  def notification_for(row)
    episodes = row.entry.subentries.to_a

    {
      subject: row.entry,
      # Denormalised so the card still reads correctly for an entry that has since been
      # deleted, and so the wording does not shift under a dismissed row.
      data: {
        'name' => row.entry.name,
        'list' => row.entry.list.name,
        # nil for an entry nothing schedules, which is most of them. The card reads as
        # what would be assumed rather than as what is happening.
        'channel' => row.channel&.name,
        'media' => row.entry.media,
        # A show does not have a runtime, its episodes do -- so for a series the useful
        # thing to say is which of them are bare, not that the show itself is. Counted off
        # the records the audit has already loaded, not with two more queries per entry.
        'episodes' => episodes.size,
        'episodes_missing' => episodes.count { |episode| CableSchedule.runtime_minutes(row.entry, episode).nil? }
      }
    }
  end
end
