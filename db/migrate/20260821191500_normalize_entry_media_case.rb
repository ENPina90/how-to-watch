# frozen_string_literal: true

# `media` is free text in the entry form, so a handful of rows were saved as
# "Movie" instead of "movie". Case-sensitive comparisons on media then skip them --
# e.g. the movie/fanedit grouping in lists/show.html.erb -- and any such row on an
# imdb provider would miss the template lookup entirely (those have no "default"
# key to fall back on, unlike the direct providers).
#
# Entry#normalize_media keeps new writes lowercase; this fixes what's already there.
class NormalizeEntryMediaCase < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE entries SET media = lower(media)
      WHERE media IS NOT NULL AND media <> lower(media)
    SQL
  end

  def down
    # The original casing isn't recorded anywhere, so there is nothing to restore.
    # Left as a no-op rather than raising so later migrations stay rollbackable.
  end
end
