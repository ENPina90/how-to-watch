# frozen_string_literal: true

# Turns an embed audit into one notification per entry VidSrc cannot play.
#
# Reconciled rather than appended, like the other two notifiers: an entry VidSrc has no
# file for is a state, and one it acquires later stops being a problem without anyone
# dismissing anything. A provider's catalogue moves both ways.
#
# The dedupe key carries what was actually asked for -- the type, the imdb id and, for a
# show, the episode -- so dismissing hides this entry as it stands. Pointing it at a
# different id, or a series at a different episode, is a new question and a new
# notification.
class UnplayableEmbedNotifier
  Result = Struct.new(:created, :removed, keyword_init: true)

  def self.call(...) = new(...).call

  # Takes the rows rather than running the audit: the scan asks VidSrc once and then both
  # marks the entries and raises the notifications off the same answer.
  def initialize(missing:)
    @missing = missing
  end

  def call
    created = 0
    removed = 0

    ActiveRecord::Base.transaction do
      admins.each do |admin|
        created += create_missing(admin, @missing)
        removed += remove_stale(admin, @missing)
      end

      removed += Notification.where(kind: Notification::UNPLAYABLE_EMBED)
                             .where.not(user_id: admins.map(&:id))
                             .delete_all
    end

    Result.new(created: created, removed: removed)
  end

  private

  def admins = @admins ||= User.where(admin: true).to_a

  def key_for(row)
    lookup = row.lookup
    episode = lookup.season && "#{lookup.season}x#{lookup.episode}"

    ["#{Notification::UNPLAYABLE_EMBED}:#{row.entry.id}", lookup.type, lookup.imdb, episode].compact.join(':')
  end

  def create_missing(admin, rows)
    existing = admin_keys(admin)

    rows.count do |row|
      next false if existing.include?(key_for(row))

      Notification.create!(
        user: admin,
        kind: Notification::UNPLAYABLE_EMBED,
        subject: row.entry,
        dedupe_key: key_for(row),
        data: {
          'name' => row.entry.name,
          'list' => row.entry.list.name,
          'media' => row.entry.media,
          'imdb' => row.lookup.imdb,
          'episode' => (row.lookup.season && "S#{row.lookup.season}E#{row.lookup.episode}"),
          'provider' => row.entry.resolved_source&.slug,
          'reason' => row.reason
        }.compact
      )
      true
    end
  end

  def remove_stale(admin, rows)
    Notification.where(user: admin, kind: Notification::UNPLAYABLE_EMBED)
                .where.not(dedupe_key: rows.map { |row| key_for(row) })
                .delete_all
  end

  def admin_keys(admin)
    Notification.where(user: admin, kind: Notification::UNPLAYABLE_EMBED).pluck(:dedupe_key).to_set
  end
end
