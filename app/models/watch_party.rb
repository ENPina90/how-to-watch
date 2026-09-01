# frozen_string_literal: true

# A room watching the same thing at the same time. The host's player is the clock: it
# reports where it is, everyone else's player is moved to match. Guests reach the room by
# its token and are then carried along -- when the host moves to the next episode the whole
# room moves with them.
#
# Only some providers can be driven this way (see Source#syncable?). On the rest the party
# still keeps everyone on the same entry and shows how far apart they are; it just cannot
# close the gap for them.
class WatchParty < ApplicationRecord
  belongs_to :list
  belongs_to :host_user, class_name: 'User'
  belongs_to :entry
  belongs_to :subentry, optional: true

  has_many :watch_party_memberships, dependent: :destroy
  has_many :members, through: :watch_party_memberships, source: :user

  validates :token, presence: true, uniqueness: true

  scope :open, -> { where(closed_at: nil) }

  before_validation :assign_token, on: :create

  # Starting a party closes whatever the host had open: the unique index allows one, and
  # silently replacing it is kinder than an error nobody can act on.
  def self.open_for(list:, host:, entry:, subentry: nil)
    transaction do
      open.where(host_user: host).find_each(&:close!)
      create!(list: list, host_user: host, entry: entry, subentry: subentry, state_at: Time.current)
    end
  end

  def open? = closed_at.nil?

  def close!
    update!(closed_at: Time.current)
    broadcast(action: 'closed')
  end

  def host?(user) = user.present? && user.id == host_user_id

  # What the host's player last said, aged forward if it has been playing since. Five
  # seconds between heartbeats is a long way into a film, so a late joiner who is handed
  # the raw number arrives that far behind everyone else.
  def projected_progress(now: Time.current)
    return player_progress unless player_status == 'playing' && state_at

    player_progress + (now - state_at)
  end

  # The host's player reporting in. Kept on the row as well as broadcast so the next guest
  # to arrive has somewhere to read it from.
  def record_state!(status:, progress:)
    update!(player_status: status, player_progress: progress, state_at: Time.current)
  end

  # Someone hit play or pause for the room. Only the status changes: a pause carries no
  # position of its own, so the room stays on the host's clock and nobody is dragged to
  # wherever the person who paused happened to be. Freezing the projection and restarting
  # the clock keeps a resume from jumping forward by however long the pause lasted.
  def record_status!(status)
    update!(player_status: status, player_progress: projected_progress, state_at: Time.current)
  end

  # Who is allowed to stop the film.
  def may_control?(user)
    host?(user) || guests_can_control?
  end

  # The host moved to a different entry or episode; everyone follows.
  def move_to!(entry:, subentry:, url:)
    update!(entry: entry, subentry: subentry, player_status: 'paused', player_progress: 0.0,
            state_at: Time.current)
    broadcast(action: 'navigate', url: url)
  end

  # Broadcasting happens in the middle of ordinary requests -- moving the room runs while
  # the host's player page is rendering, and closing it runs on their way out. A pubsub
  # backend that is down or unreachable must not take the player page down with it: the
  # party is something the page has, not something it is. The room falls out of step and
  # says so; the film keeps playing.
  def broadcast(payload)
    WatchPartyChannel.broadcast_to(self, payload)
  rescue StandardError => e
    Rails.logger.error "Watch party #{id} could not broadcast #{payload[:action]}: #{e.class}: #{e.message}"
    nil
  end

  # Who is here. Anyone whose page has not checked in for a while has closed the tab or
  # gone to sleep; they are not in the room any more, but their membership is left alone so
  # coming back does not need a new invitation.
  PRESENCE_WINDOW = 45.seconds

  def present_memberships
    watch_party_memberships.includes(:user).where(last_seen_at: PRESENCE_WINDOW.ago..)
  end

  def join!(user)
    membership = watch_party_memberships.find_or_initialize_by(user: user)
    membership.update!(last_seen_at: Time.current)
    membership
  end

  private

  def assign_token
    self.token ||= SecureRandom.urlsafe_base64(12)
  end
end
