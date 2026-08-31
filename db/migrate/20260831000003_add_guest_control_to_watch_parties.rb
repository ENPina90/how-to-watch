# frozen_string_literal: true

# Whether anyone in the room can stop the film, or only the host. Defaults to on: a room
# where the only person who can pause is the one who started it is the surprising
# arrangement, not the other way round.
class AddGuestControlToWatchParties < ActiveRecord::Migration[8.1]
  def change
    add_column :watch_parties, :guests_can_control, :boolean, null: false, default: true
  end
end
