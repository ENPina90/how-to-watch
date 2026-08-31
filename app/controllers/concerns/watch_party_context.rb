# frozen_string_literal: true

# The room this request is being made from, if any. The token lives in the session, so a
# party follows the person around the site rather than being a property of one page.
module WatchPartyContext
  extend ActiveSupport::Concern

  included do
    helper_method :current_watch_party
  end

  def current_watch_party
    return @current_watch_party if defined?(@current_watch_party)

    @current_watch_party = begin
      token = session[:watch_party_token]
      party = WatchParty.open.find_by(token: token) if token.present?
      # A room that has ended stops being context the moment it does; leaving the token in
      # the session would put a dead party bar on every page.
      session.delete(:watch_party_token) if token.present? && party.nil?
      party
    end
  end

  # The host's page is the room's source of truth for *what* is playing. Reading their
  # player page is what moves everyone else, so this runs on `watch` rather than on the
  # navigation actions -- every one of those ends in a redirect to here anyway, and the
  # sidebar's episode links reach it directly without passing through any of them.
  def follow_host_navigation(party, entry, subentry, url)
    return unless party&.host?(current_user)
    return if party.entry_id == entry.id && party.subentry_id == subentry&.id

    party.move_to!(entry: entry, subentry: subentry, url: url)
  end
end
