# frozen_string_literal: true

# The room's socket. Three different things travel over it: the host's player reporting
# where it is, anyone permitted hitting play or pause, and people saying they are still
# here.
#
# Authority is checked on every message rather than at subscribe time. The host is the only
# one whose clock the room follows, so a guest posting `state` must not be able to drag
# everyone else around -- and whether a guest may stop the film at all is the host's to
# change while everyone is already connected.
class WatchPartyChannel < ApplicationCable::Channel
  def subscribed
    room = party
    return reject unless room

    room.join!(current_user)
    stream_for room

    # Whoever just arrived needs the room's current state; everyone else needs to know
    # they are here.
    transmit({ action: 'state', **state_payload(room) })
    broadcast_presence(room)
  end

  def unsubscribed
    room = party
    return unless room

    # Their page has gone. Drop the heartbeat rather than the membership so a reload puts
    # them straight back in the room.
    room.watch_party_memberships.where(user: current_user).update_all(last_seen_at: 2.minutes.ago)
    broadcast_presence(room)

    # That may have been the last of them. Checked again after the grace period rather
    # than now, because leaving is also what a reload looks like from here.
    return if room.present_memberships.any?

    CloseAbandonedWatchPartiesJob.set(wait: WatchParty::ABANDONED_AFTER).perform_later
  end

  # The host's player reporting in.
  def state(data)
    room = party
    return unless room&.host?(current_user)

    status = data['status'] == 'playing' ? 'playing' : 'paused'
    room.record_state!(status: status, progress: data['progress'].to_f)
    # The host's player reporting in is the host still being here. They never send
    # `heartbeat` -- that is the guests' message -- so without this they age out of the
    # member list while sitting in the room they are hosting.
    touch_presence(room)
    WatchPartyChannel.broadcast_to(room, { action: 'state', **state_payload(room) })
  end

  # Someone hit play or pause for the room. Unlike `state` this is not a clock -- it
  # carries no position, only the intent -- so a guest stopping the film cannot also drag
  # everyone to where they happen to be sitting.
  #
  # `by` is what stops it echoing: the person who pressed it has already done the thing,
  # and acting on their own message back would fight their next press.
  def control(data)
    room = party
    return unless room&.may_control?(current_user)

    status = data['status'] == 'playing' ? 'playing' : 'paused'
    room.record_status!(status)
    touch_presence(room)
    WatchPartyChannel.broadcast_to(room, { action: 'control', status: status, by: current_user.id })
  end

  # The host deciding whether the room can stop the film. Over the socket rather than a
  # form: a reload here would rebuild the player iframe and lose everyone's place.
  def permission(data)
    room = party
    return unless room&.host?(current_user)

    room.update!(guests_can_control: data['allowed'] ? true : false)
    WatchPartyChannel.broadcast_to(room,
                                   { action: 'settings', guests_can_control: room.guests_can_control? })
  end

  # A guest saying where their own player is, so presence stays fresh.
  def heartbeat(_data)
    room = party
    return unless room

    touch_presence(room)
    broadcast_presence(room)
  end

  private

  # Each message is its own read of the room. A channel instance lives as long as the
  # socket, so a copy loaded when someone joined still believes whatever was true then:
  # it would record a pause against a position from an hour ago, and would go on letting a
  # guest stop the film after the host had closed that off. Neither shows up as an error --
  # Active Record simply writes nothing, because against the stale copy nothing changed.
  # Read once, at the top of whichever message is being handled, and passed down from
  # there. Not memoised on the instance: that copy would go stale over the life of the
  # socket, which is the bug this replaced.
  def party
    WatchParty.open.find_by(token: params[:token])
  end

  def touch_presence(room)
    room.watch_party_memberships.where(user: current_user).update_all(last_seen_at: Time.current)
  end

  def state_payload(room)
    {
      status: room.player_status,
      progress: room.projected_progress,
      entry_id: room.entry_id,
      subentry_id: room.subentry_id,
      guests_can_control: room.guests_can_control?,
      at: Time.current.to_f,
    }
  end

  # Who is in the room only changes when someone arrives or goes quiet, but every guest's
  # player reports in every few seconds. Broadcasting an unchanged list to everyone on each
  # of those was most of the traffic on this socket and told nobody anything.
  def broadcast_presence(room)
    members = room.present_memberships.map do |membership|
      { id: membership.user_id, name: membership.user.display_name, host: room.host?(membership.user) }
    end

    return if members == @last_members

    @last_members = members
    WatchPartyChannel.broadcast_to(room, { action: 'presence', members: members })
  end
end
