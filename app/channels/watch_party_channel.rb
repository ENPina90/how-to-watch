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
    transmit({ action: 'state', **state_payload })
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
    # The host's player reporting in is the host still being here. They never send
    # `heartbeat` -- that is the guests' message -- so without this they age out of the
    # member list while sitting in the room they are hosting.
    touch_presence
    WatchPartyChannel.broadcast_to(@party, { action: 'state', **state_payload })
  end

  # Someone hit play or pause for the room. Unlike `state` this is not a clock -- it
  # carries no position, only the intent -- so a guest stopping the film cannot also drag
  # everyone to where they happen to be sitting.
  #
  # `by` is what stops it echoing: the person who pressed it has already done the thing,
  # and acting on their own message back would fight their next press.
  def control(data)
    return unless @party&.may_control?(current_user)

    status = data['status'] == 'playing' ? 'playing' : 'paused'
    @party.record_status!(status)
    touch_presence
    WatchPartyChannel.broadcast_to(@party, { action: 'control', status: status, by: current_user.id })
  end

  # The host deciding whether the room can stop the film. Over the socket rather than a
  # form: a reload here would rebuild the player iframe and lose everyone's place.
  def permission(data)
    return unless @party&.host?(current_user)

    @party.update!(guests_can_control: data['allowed'] ? true : false)
    WatchPartyChannel.broadcast_to(@party,
                                   { action: 'settings', guests_can_control: @party.guests_can_control? })
  end

  # A guest saying where their own player is, so the bar can show the gap.
  def heartbeat(data)
    return unless @party

    touch_presence
    broadcast_presence(progress: data['progress'])
  end

  private

  def touch_presence
    @party.watch_party_memberships.where(user: current_user).update_all(last_seen_at: Time.current)
  end

  def state_payload
    {
      status: @party.player_status,
      progress: @party.projected_progress,
      entry_id: @party.entry_id,
      subentry_id: @party.subentry_id,
      guests_can_control: @party.guests_can_control?,
      at: Time.current.to_f,
    }
  end

  def broadcast_presence(progress: nil)
    members = @party.present_memberships.map do |membership|
      { id: membership.user_id, name: membership.user.display_name, host: @party.host?(membership.user) }
    end

    WatchPartyChannel.broadcast_to(@party, { action: 'presence', members: members, progress: progress })
  end
end
