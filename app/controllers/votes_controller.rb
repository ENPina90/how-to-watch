# frozen_string_literal: true

# Voting on what to watch next. One screen in the room puts up a shortlist and shows a QR
# code; everyone else scans it, sees the same shortlist on their phone, and taps one. No
# account, no name, nothing typed -- a phone is known only by a random token in its own
# cookie, which is what stops one device voting twice.
class VotesController < ApplicationController
  # Whoever scans the code is a guest: reading the ballot and voting on it are the two
  # things this app lets you do without an account. Putting the shortlist up, editing it
  # and closing the round still need someone who can edit the channel.
  # Skips the check AccessControl installs, so the ballot stays open whatever the site's
  # access mode is: a room scanning a code is not the same question as who may browse.
  skip_before_action :authenticate_user_unless_guest_allowed!, only: %i[show cast]

  before_action :set_list
  before_action :set_session, only: %i[cast close remove_option]
  before_action :require_editor, only: %i[create close remove_option]

  def show
    @vote_session = @list.vote_sessions.open.last || @list.vote_sessions.order(:created_at).last
    @standings = @vote_session&.standings || []
    @voted_option_id = @vote_session&.votes&.find_by(voter_token: voter_token)&.vote_option_id

    return render :show_mobile, layout: 'mobile' if mobile_request?

    @qr = qr_svg(list_vote_url(@list))
  end

  # Puts a shortlist up, replacing any round still open on this channel.
  def create
    count = params[:count].to_i.clamp(2, 12)
    @vote_session = VoteSession.open_for(@list, count)

    redirect_to list_vote_path(@list), notice: "#{@vote_session.vote_options.count} up for a vote."
  end

  def cast
    option = @vote_session.vote_options.find(params[:option_id])

    unless @vote_session.open?
      return respond_to do |format|
        format.html { redirect_to list_vote_path(@list), alert: 'Voting has closed.' }
        format.json { render json: { error: 'Voting has closed.' }, status: :gone }
      end
    end

    @vote_session.vote_for(option, voter_token)

    respond_to do |format|
      format.html { redirect_to list_vote_path(@list), notice: "Voted for #{option.entry.name}." }
      format.json { render json: { voted: option.id } }
    end
  end

  def close
    @vote_session.close!

    redirect_to list_vote_path(@list)
  end

  def remove_option
    @vote_session.vote_options.find(params[:option_id]).destroy

    redirect_to list_vote_path(@list)
  end

  private

  def set_list
    @list = List.find(params[:list_id])
  end

  def set_session
    @vote_session = @list.vote_sessions.order(:created_at).last

    redirect_to list_vote_path(@list), alert: 'Nothing is up for a vote.' if @vote_session.nil?
  end

  def require_editor
    return if current_user && current_user.can_edit_list?(@list)

    redirect_to list_vote_path(@list), alert: 'Only someone who can edit this channel can run the vote.'
  end

  # The device, not the person. A signed cookie so a phone keeps the same identity across
  # its own visits, and so the token cannot be edited into someone else's.
  def voter_token
    cookies.signed[:voter_token] ||= {
      value: SecureRandom.uuid,
      expires: 1.year.from_now,
      httponly: true
    }

    cookies.signed[:voter_token]
  end

  # Drawn as an inline SVG: no file to store, nothing to fetch, and it stays sharp on
  # whatever the room is looking at.
  def qr_svg(url)
    RQRCode::QRCode.new(url).as_svg(module_size: 5, standalone: true, use_path: true).html_safe
  end
end
