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
class BrokenPosterNotifier < AdminStateNotifier
  Result = Struct.new(:checked, :broken, :created, :removed, keyword_init: true)

  def initialize(audit: PosterAudit.new)
    @audit = audit
  end

  def call
    audit = @audit.call
    created, removed = reconcile(audit.broken)

    Result.new(checked: audit.checked, broken: audit.broken.size, created: created, removed: removed)
  end

  private

  def kind = Notification::BROKEN_POSTER

  # Digested rather than carried whole: a pic column can hold a URL of any length, and the
  # key only has to change when the URL does.
  def key_for(row) = "#{kind}:#{row.entry.id}:#{Digest::SHA256.hexdigest(row.url.to_s)[0, 16]}"

  def notification_for(row)
    {
      subject: row.entry,
      data: {
        'name' => row.entry.name,
        'list' => row.entry.list.name,
        'source' => row.source,
        'reason' => row.reason,
        'url' => row.url.to_s.truncate(500)
      }
    }
  end
end
