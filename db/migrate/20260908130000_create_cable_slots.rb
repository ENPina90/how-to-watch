# frozen_string_literal: true

# One programme on one channel at one time -- the cable schedule, a row per slot.
#
# A row rather than a blob per channel-day because the question the player asks is "what is
# on this channel right now", which this answers with one indexed range lookup. A jsonb day
# would have to be loaded whole and scanned in Ruby on every frame of every channel change,
# and buys nothing back: the schedule is written once a day and read constantly.
#
# The schedule is the same for everybody. Nothing here references a user, and nothing that
# reads it may write one -- that is the difference between /cable and /watch.
class CreateCableSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :cable_slots do |t|
      t.references :list, null: false, foreign_key: { on_delete: :cascade }
      # An entry deleted mid-day takes its slots with it. The alternative is a channel that
      # 500s at 3pm because something was tidied up at lunchtime.
      t.references :entry, null: false, foreign_key: { on_delete: :cascade }
      # The episode, for a series or anime entry. Null for anything that is one programme.
      t.references :subentry, foreign_key: { on_delete: :cascade }
      # The cable day this belongs to, in CableSchedule.zone -- not a UTC date. It is what
      # a regeneration deletes and what the pruner counts back from.
      t.date :airs_on, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :position, null: false

      t.timestamps
    end

    # The player's question: one channel, the row covering this instant.
    add_index :cable_slots, %i[list_id starts_at ends_at]
    # One programme per ordinal per channel-day, so a regeneration that runs twice cannot
    # leave a day with two overlapping schedules.
    add_index :cable_slots, %i[list_id airs_on position], unique: true
  end
end
