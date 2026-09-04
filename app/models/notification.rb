# frozen_string_literal: true

# Something the app wants to tell one person about.
#
# Deliberately generic. Expiry warnings are the first kind and currently the only one, but
# the shape is meant to carry "somebody subscribed to your channel" and the rest without
# a second table: `kind` says what sort of thing it is, `subject` points at what it is
# about, and anything specific to one kind lives in `data`.
#
# Dismissal is per person and permanent for that notification. What makes that safe for a
# warning that is really a *state* rather than an event -- a provider is expiring, and goes
# on expiring after you dismiss it -- is `dedupe_key`: it carries the date being warned
# about, so renewing the provider retires the dismissed row and a later warning about the
# new date is a new notification. See SourceExpiryNotifier.
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :subject, polymorphic: true, optional: true

  SOURCE_EXPIRING = 'source_expiring'

  # Kinds only an admin should ever see. Enforced at creation -- the notifier only writes
  # them for admins -- and again on read, so an account that loses its admin flag stops
  # seeing them without needing a sweep.
  ADMIN_ONLY_KINDS = [SOURCE_EXPIRING].freeze

  validates :kind, presence: true
  validates :dedupe_key, presence: true, uniqueness: { scope: :user_id }

  scope :active, -> { where(dismissed_at: nil) }
  scope :newest_first, -> { order(created_at: :desc) }

  # What this person should actually be shown. The admin check is the read-side half of
  # ADMIN_ONLY_KINDS.
  scope :visible_to, lambda { |user|
    scope = where(user: user)
    user&.admin? ? scope : scope.where.not(kind: ADMIN_ONLY_KINDS)
  }

  def dismissed? = dismissed_at.present?

  def dismiss!
    return if dismissed?

    update!(dismissed_at: Time.current)
  end
end
