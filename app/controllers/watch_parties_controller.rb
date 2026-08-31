# frozen_string_literal: true

# Starting, joining and ending a watch party. The party itself lives on the player page --
# this only opens the room and puts people in it.
class WatchPartiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_party, only: %i[show destroy]

  # Join by token: put the guest where the host is, and remember the room for as long as
  # they stay on the player. The session is what the player page reads to decide whether to
  # render the party bar at all.
  def show
    unless @party.open?
      session.delete(:watch_party_token)
      return redirect_to list_path(@party.list), alert: 'That watch party has ended.'
    end

    @party.join!(current_user)
    session[:watch_party_token] = @party.token

    redirect_to watch_entry_path(@party.entry, channel: @party.list_id,
                                               subentry: @party.subentry_id)
  end

  # The host opens a room on whatever they are watching now.
  def create
    entry = Entry.find(params[:entry_id])
    list  = List.find_by(id: params[:channel]) || entry.list
    subentry = entry.subentries.find_by(id: params[:subentry_id])

    party = WatchParty.open_for(list: list, host: current_user, entry: entry, subentry: subentry)
    session[:watch_party_token] = party.token

    redirect_back fallback_location: watch_entry_path(entry),
                  notice: 'Watch party started. Share the link to invite people.'
  end

  def destroy
    # Ending the room is the host's to do; anyone else is only leaving it.
    if @party.host?(current_user)
      @party.close!
      notice = 'Watch party ended.'
    else
      @party.watch_party_memberships.where(user: current_user).destroy_all
      notice = 'You left the watch party.'
    end

    session.delete(:watch_party_token)
    redirect_back fallback_location: list_path(@party.list), notice: notice
  end

  private

  def set_party
    @party = WatchParty.find_by!(token: params[:token])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: 'That watch party link is not valid.'
  end
end
