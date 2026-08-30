class AddLetterboxdScoreToEntries < ActiveRecord::Migration[8.0]
  def change
    # Letterboxd rates 0.5-5.0 in half-star steps. Stored as given rather than doubled
    # into the 1-10 `user_entries.review` scale, so the card can show the stars the
    # member actually picked.
    add_column :entries, :letterboxd_score, :float
  end
end
