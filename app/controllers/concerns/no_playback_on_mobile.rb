# frozen_string_literal: true

# The phone view does not play anything.
#
# That is a decision about what the phone view is for rather than a limitation: it exists
# for adding something to a channel while out, marking something watched, and reading the
# cable listings. Watching happens on a screen worth watching on.
#
# Enforced here rather than by leaving the links out, because a link is not the only way to
# reach a page -- a bookmark, a shared address, the back button and a stale tab all arrive
# at the same place. So the pages that play refuse in the phone view and say where to go
# instead, and offer the way out of it: somebody who really does mean to watch on their
# phone can switch to the full view and carry on.
module NoPlaybackOnMobile
  extend ActiveSupport::Concern

  included do
    before_action :refuse_playback_on_mobile
  end

  private

  def refuse_playback_on_mobile
    return unless mobile_request?

    redirect_to playback_refusal_path,
                alert: 'Watching is off in the phone view. Switch to the full site to play this.'
  end

  # Somewhere useful rather than the front door: the channel this was going to play from,
  # if the request named one.
  def playback_refusal_path
    channel = @list || @entry&.list

    channel ? list_path(channel) : root_path
  end
end
