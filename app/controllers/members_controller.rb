# frozen_string_literal: true

# Somebody else's profile, as against `/profile` -- which is the singular resource above
# this one in the routes, is always the signed-in member's own, and is a settings form.
# Two different questions about a user, so two controllers rather than one action guessing
# which it has been asked.
#
# Not listed in AccessControl, so it falls through to Devise and a signed-out visitor
# cannot reach it. What somebody has been watching is a reasonable thing to show the other
# members of a shared channel and not a reasonable thing to leave open to the internet.
class MembersController < ApplicationController
  before_action :set_member

  # How much of a watch history is worth putting on a page. Long enough to read as a
  # history, short enough that a member with four thousand tracked entries does not send
  # four thousand rows.
  RECENT_LIMIT = 25

  def show
    @lists_count = @member.lists.count
    # Entries in the channels this member owns: `entries` has no user of its own, so who
    # added one is a question about which channel it is in.
    @entries_count = Entry.where(list_id: @member.lists.select(:id)).count
    @watched_count = @member.user_entries.completed.count

    # Newest first by whichever timestamp the row actually has. `completed_at` is only set
    # when something is ticked, `last_watched_at` only when the player has reported, and
    # the oldest rows predate both -- ordering on any one of them alone buries everything
    # that happens to be missing it.
    @recent = @member.user_entries
                     .includes(entry: :list)
                     .order(Arel.sql('COALESCE(completed_at, last_watched_at, user_entries.updated_at) DESC'))
                     .limit(RECENT_LIMIT)
  end

  private

  def set_member
    @member = User.find(params[:id])
  end
end
