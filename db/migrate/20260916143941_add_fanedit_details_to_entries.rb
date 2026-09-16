# frozen_string_literal: true

# What a fanedit is, as against what it plays like. A fanedit's name is the editor's title
# for it -- "Despecialized", "The Last Jedi: Rekindled" -- which says nothing about what it
# was cut from or who cut it, and those are the two things somebody scanning a channel of
# them wants to know. The metadata APIs have no record of any of it, so it is typed in.
#
# `faneditor` is already here (May 2024) and holds exactly what it says; these three join
# it. `original` names the source material rather than pointing at it: the entry's own
# `imdb`/`letterboxd_slug` already identify the film, and the card links the name through
# those when they are filled in. `fanedit_link` is the editor's page for the cut --
# fanedits.org, a forum thread, wherever it was published -- and is not checked by the
# broken-source sweep, which is about things the player loads.
#
# `fanedit_type` is one of Entry::FANEDIT_TYPES, validated in the model rather than by a
# check constraint: the set is a piece of vocabulary that will grow, and growing it should
# be an edit to one constant and not a migration.
#
# All nullable. Every fanedit already in the database has none of this, and a cut nobody
# has got round to describing is still a cut that plays.
class AddFaneditDetailsToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :original, :string
    add_column :entries, :fanedit_link, :string
    add_column :entries, :fanedit_type, :string
  end
end
