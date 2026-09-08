# frozen_string_literal: true

# The adverts between programmes, and the gap they fill.
#
# A cable channel does not cut from one film straight into the next -- it pads to the top of
# the hour, or the half, or the five, and fills the gap. The schedule now does the same: a
# programme's slot runs to the next five-minute mark, and whatever is left over after the
# film has ended is a commercial break. Every slot therefore starts on :00, :05, :10 and so
# on, which is what a listing has always looked like and what it never quite did here.
#
# The reels are compilations, one per year or era, kept in their own table rather than as
# entries: an entry carries a poster, an IMDb id, a place in a channel and a row per viewer
# who has watched it, and a commercial break has none of those and is watched by nobody.
class CreateCommercialReels < ActiveRecord::Migration[8.1]
  def change
    create_table :commercial_reels do |t|
      # What it is called in the admin, e.g. "1987" or "1940s". Display only; the years
      # below are what is matched against.
      t.string :label, null: false
      # The span this reel covers, inclusive. A single year has both the same.
      t.integer :starts_year, null: false
      t.integer :ends_year, null: false
      t.string :youtube_id, null: false
      # Runtime, where it is known. Only used to widen the window a break may start in, so
      # it is allowed to be missing -- the window falls back to something safely small.
      t.integer :duration_seconds

      t.timestamps
    end

    add_index :commercial_reels, %i[starts_year ends_year]
    add_index :commercial_reels, :youtube_id, unique: true

    change_table :cable_slots, bulk: true do |t|
      # When the programme itself ends. The slot runs past it, to the next five-minute mark,
      # and the difference is the break. Null means the film ends exactly on the mark and
      # there is nothing to fill.
      t.datetime :break_starts_at
      # Which reel, and how far into it, chosen once when the day is laid out rather than
      # per viewer -- two people on the same channel at the same second have to see the same
      # advert, for the same reason they see the same film.
      t.references :break_reel, foreign_key: { to_table: :commercial_reels, on_delete: :nullify }
      t.integer :break_offset
    end
  end
end
