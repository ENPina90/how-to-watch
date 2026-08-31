# frozen_string_literal: true

# The room's socket. Everything on it is either the host's player reporting where it is, or
# a guest saying they are still here.
#
# Authority is checked on every message rather than at subscribe time: the host is the only
# one whose clock the room follows, so a guest posting `state` must not be able to drag
# everyone else around.
class WatchPartyChannel < ApplicationCable::Channel
  def subscribed
    party = WatchParty.open.find_by(token: params[:token])
    return reject unless party

    @party = party
    party.join!(current_user)
    stream_for party

    # Whoever just arrived needs the room's current state; everyone else needs to know
    # they are here.
    transmit(action: 'state', **state_payload)
    broadcast_presence
  end

  def unsubscribed
    return unless @party

    # Their page has gone. Drop the heartbeat rather than the membership so a reload puts
    # them straight back in the room.
    @party.watch_party_memberships.where(user: current_user).update_all(last_seen_at: 2.minutes.ago)
    broadcast_presence
  end

  # The host's player reporting in.
  def state(data)
    return unless @party&.host?(current_user)

    status = data['status'] == 'playing' ? 'playing' : 'paused'
    @party.record_state!(status: status, progress: data['progress'].to_f)
    WatchPartyChannel.broadcast_to(@party, action: 'state', **state_payload)
  end

  # A guest saying where their own player is, so the bar can show the gap.
  def heartbeat(data)
    return unless @party

    @party.watch_party_memberships
          .where(user: current_user)
          .update_all(last_seen_at: Time.current)

    broadcast_presence(progress: data['progress'])
  end

  private

  def state_payload
    {
      status: @party.player_status,
      progress: @party.projected_progress,
      entry_id: @party.entry_id,
      subentry_id: @party.subentry_id,
      at: Time.current.to_f,
    }
  end

  def broadcast_presence(progress: nil)
    members = @party.present_memberships.map do |membership|
      { id: membership.user_id, name: membership.user.display_name, host: @party.host?(membership.user) }
    end

    WatchPartyChannel.broadcast_to(@party, action: 'presence', members: members, progress: progress)
  end
end
