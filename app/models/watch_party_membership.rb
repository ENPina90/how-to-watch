# frozen_string_literal: true

# One person in a room. `last_seen_at` is a heartbeat from their open page rather than a
# join time, so presence answers "is their player still there" and not "did they ever
# click the link".
class WatchPartyMembership < ApplicationRecord
  belongs_to :watch_party
  belongs_to :user

  # What the party bar shows for this person: how far their own player is from the host's.
  # Not stored -- it is only true for as long as the number that produced it.
  attr_accessor :drift
end
