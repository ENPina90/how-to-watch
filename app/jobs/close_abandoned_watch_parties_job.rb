# frozen_string_literal: true

# Closes rooms nobody is in any more.
#
# Queued twice over, because neither trigger covers the other. The socket of the last
# person to leave queues one of these on a delay, which is what ends a room promptly when
# everybody simply goes somewhere else; and the schedule runs it periodically, which is
# what catches rooms whose sockets never got the chance to say goodbye -- a deploy, a
# crashed worker, a laptop closed mid-film.
#
# Idempotent and self-checking: it re-reads presence when it runs rather than trusting
# whatever was true when it was queued, so somebody who left and came back inside the
# grace period keeps their room.
class CloseAbandonedWatchPartiesJob < ApplicationJob
  queue_as :default

  def perform
    closed = WatchParty.close_abandoned!
    Rails.logger.info("Closed #{closed} abandoned watch #{'party'.pluralize(closed)}") if closed.positive?
  end
end
