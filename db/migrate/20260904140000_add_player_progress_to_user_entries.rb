class AddPlayerProgressToUserEntries < ActiveRecord::Migration[8.0]
  # Where this member's player had reached, in seconds, so the entry picks up where they
  # left it. Per-member rather than per-entry for the same reason the Letterboxd score is:
  # two people watching the same film are not in the same place in it.
  #
  # Float because the player reports fractional seconds, and null because "never played"
  # is a different thing from "played and rewound to the start".
  def change
    add_column :user_entries, :player_progress, :float
  end
end
