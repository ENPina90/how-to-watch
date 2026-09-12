# frozen_string_literal: true

# Where a channel sits on the cable dial, set by hand rather than fallen out of the table.
#
# The dial was ordered by `id` -- deliberately, so that renaming a channel could not
# silently move it, the way renaming a television channel does not move it. But id order is
# the order the rows happened to be created in, which is nobody's idea of a line-up: the
# channel you watch most is wherever it was made, and the only way to move it was to delete
# and recreate it. So the ordering becomes a column an admin drags on /admin/cable, and the
# two things id order was standing in for are kept: the order is stable across page loads,
# and it does not change when a channel is renamed.
#
# Nullable, and null sorts last in Postgres under a plain ASC. A channel marked default by
# some other path -- a console session, a fixture, a migration that predates this one --
# therefore lands at the end of the dial rather than at the front of it, which is what
# "added to the dial" should look like.
#
# No index. The dial is single digits of rows and the existing index on `default` is what
# narrows the query; an index to order six rows would cost more to keep than it saves.
class AddCablePositionToLists < ActiveRecord::Migration[8.1]
  def up
    add_column :lists, :cable_position, :integer

    # Today's dial, numbered in the order it is already in, so the channels do not move
    # under anybody the moment this deploys. Only the channels on the dial get a number:
    # the column means nothing for a channel that is not on it.
    execute <<~SQL.squish
      UPDATE lists SET cable_position = numbered.rank
      FROM (
        SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rank
        FROM lists WHERE "default" = TRUE
      ) AS numbered
      WHERE lists.id = numbered.id
    SQL
  end

  def down
    remove_column :lists, :cable_position
  end
end
