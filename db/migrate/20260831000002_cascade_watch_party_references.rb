# frozen_string_literal: true

# Lists delete their entries with `delete_all` and entries do the same to their subentries,
# so nothing in Rails gets a chance to clear a party pointing at them. The cascade has to
# be the database's, or deleting a channel fails on a foreign key.
#
# A borrowed entry is why this cannot be solved with `dependent:` on List alone: a party
# watching from one channel can point at an entry that lives in another, and destroying
# that other channel is what would break.
class CascadeWatchPartyReferences < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :watch_parties, :entries
    remove_foreign_key :watch_parties, :subentries
    remove_foreign_key :watch_parties, :lists
    remove_foreign_key :watch_parties, column: :host_user_id

    add_foreign_key :watch_parties, :entries, on_delete: :cascade
    # The party outlives the episode: it is still watching the entry, just no longer
    # pointed at one of its episodes.
    add_foreign_key :watch_parties, :subentries, on_delete: :nullify
    add_foreign_key :watch_parties, :lists, on_delete: :cascade
    add_foreign_key :watch_parties, :users, column: :host_user_id, on_delete: :cascade
  end

  def down
    remove_foreign_key :watch_parties, :entries
    remove_foreign_key :watch_parties, :subentries
    remove_foreign_key :watch_parties, :lists
    remove_foreign_key :watch_parties, column: :host_user_id

    add_foreign_key :watch_parties, :entries
    add_foreign_key :watch_parties, :subentries
    add_foreign_key :watch_parties, :lists
    add_foreign_key :watch_parties, :users, column: :host_user_id
  end
end
