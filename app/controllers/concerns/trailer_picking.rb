# frozen_string_literal: true

# The next trailer, for the two pages that play them: /trailers, and channel 0 on /cable.
#
# What this browser was shown lately lives in the session rather than in a table. It is a
# note about the last hour on one screen, not something to keep, and a row per trailer would
# be a write every two minutes for every viewer -- whereas the session is already written as
# a member moves around (see ApplicationController#cable_now_playing).
module TrailerPicking
  extend ActiveSupport::Concern

  private

  # Not noted while the page is only being warmed. Nobody has seen that trailer, and marking
  # it seen would pass over the one the viewer lands on.
  def next_trailer
    seen = Array(session[:trailers_seen])
    trailer = TrailerReel.new(user: current_user, seen: seen).pick

    session[:trailers_seen] = TrailerReel.remember(seen, trailer.youtube_id) if trailer && !preloading?

    trailer
  end
end
