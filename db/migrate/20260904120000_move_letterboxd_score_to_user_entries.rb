class MoveLetterboxdScoreToUserEntries < ActiveRecord::Migration[8.0]
  # A Letterboxd rating is one member's opinion, so it belongs on their own tracking row
  # rather than on the entry everybody sharing the channel sees. Living on `entries` also
  # capped it at one score per film: the same movie in two members' diaries had to pick
  # one of their ratings.
  def up
    # Letterboxd rates 0.5-5.0 in half-star steps. Stored as given rather than doubled
    # into the 1-10 `user_entries.review` scale, so the card can show the stars the
    # member actually picked.
    add_column :user_entries, :letterboxd_score, :float

    # Every score written so far came from a diary import, so the member it belongs to is
    # the owner of the channel the entry sits in. Any tracking row that is missing is one
    # the sync will make on its next pass.
    execute(<<~SQL.squish)
      UPDATE user_entries
      SET letterboxd_score = entries.letterboxd_score
      FROM entries
      INNER JOIN lists ON lists.id = entries.list_id
      WHERE entries.id = user_entries.entry_id
        AND lists.user_id = user_entries.user_id
        AND lists.letterboxd = TRUE
        AND entries.letterboxd_score IS NOT NULL
    SQL

    remove_column :entries, :letterboxd_score
  end

  def down
    add_column :entries, :letterboxd_score, :float

    # Back to one score per entry: the channel owner's, which is the only one the column
    # could ever hold.
    execute(<<~SQL.squish)
      UPDATE entries
      SET letterboxd_score = user_entries.letterboxd_score
      FROM user_entries, lists
      WHERE user_entries.entry_id = entries.id
        AND lists.id = entries.list_id
        AND user_entries.user_id = lists.user_id
        AND lists.letterboxd = TRUE
        AND user_entries.letterboxd_score IS NOT NULL
    SQL

    remove_column :user_entries, :letterboxd_score
  end
end
