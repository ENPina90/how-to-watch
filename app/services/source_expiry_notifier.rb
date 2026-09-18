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
class SourceExpiryNotifier < AdminStateNotifier
  Result = Struct.new(:created, :removed, keyword_init: true)

  def initialize(now: Date.current)
    @now = now
  end

  def call
    created, removed = reconcile(due_sources)

    Result.new(created: created, removed: removed)
  end

  private

  def kind = Notification::SOURCE_EXPIRING

  # Expiring sources, soonest first. Memoised: reconcile asks for them once per admin.
  def due_sources
    @due_sources ||= Source.active.expiring_by(@now + Source::EXPIRY_WARNING_WINDOW).to_a
  end

  # The date is in the key: renewing a source past the window changes the warning rather
  # than leaving a dismissed one hiding the next one.
  def key_for(source) = "#{kind}:#{source.id}:#{source.valid_until}"

  def notification_for(source)
    {
      subject: source,
      # Denormalised so the page can render a warning about a source that has since been
      # deleted, and so the wording does not silently change under a dismissed row.
      data: { 'name' => source.name, 'slug' => source.slug, 'valid_until' => source.valid_until.to_s }
    }
  end
end
