# frozen_string_literal: true

# A slot on a decade channel. The decades at the end of the cable dial are not lists -- see
# CableEra -- so a programme on one names its channel by key rather than by list id.
#
# Exactly one of the two, and the database checks it: a slot on no channel is a row nothing
# can reach, and a slot on both would be listed twice. The era rows get the uniqueness the list
# rows already have from a partial index of their own. The existing list index needs nothing:
# Postgres counts the null list_id of every era row as distinct.
class AddEraToCableSlots < ActiveRecord::Migration[8.1]
  def change
    add_column :cable_slots, :era, :string
    change_column_null :cable_slots, :list_id, true

    add_index :cable_slots, %i[era airs_on position], unique: true, where: "era IS NOT NULL"
    add_index :cable_slots, %i[era starts_at ends_at], where: "era IS NOT NULL"

    add_check_constraint :cable_slots, "(list_id IS NULL) <> (era IS NULL)", name: "cable_slots_one_channel"
  end
end
