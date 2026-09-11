# frozen_string_literal: true

# The one channel a member has singled out as theirs: where "add to favourites" puts a
# film, and what the phone view opens on.
#
# That channel already existed -- every account is created with one, and it was found by
# the `mobile` flag on it -- but the flag is a property of the channel rather than a choice
# the member made, so there was no way to point it somewhere else. A column on the member
# says whose favourite it is and lets them move it; one column also says, structurally,
# that there is only ever one.
#
# Nullified rather than cascading on delete: deleting the channel you had favourited should
# leave you with no favourite, not with no account.
class AddFavoriteListToUsers < ActiveRecord::Migration[8.1]
  def up
    add_reference :users, :favorite_list,
                  foreign_key: { to_table: :lists, on_delete: :nullify }

    # Everybody who already has the auto-created channel keeps it as their favourite, so
    # nothing about today's behaviour changes for an existing account.
    execute <<~SQL.squish
      UPDATE users
      SET favorite_list_id = (
        SELECT lists.id FROM lists
        WHERE lists.user_id = users.id AND lists.mobile = TRUE
        ORDER BY lists.created_at, lists.id
        LIMIT 1
      )
    SQL
  end

  def down
    remove_reference :users, :favorite_list, foreign_key: { to_table: :lists }
  end
end
