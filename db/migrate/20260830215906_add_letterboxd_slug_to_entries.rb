class AddLetterboxdSlugToEntries < ActiveRecord::Migration[8.0]
  def change
    # Letterboxd's own name for the film, as in /film/<slug>/. Only the canonical film
    # URL accepts the /review/ suffix that opens the review prompt -- the /imdb/<id>/ and
    # /tmdb/<id>/ shortcuts redirect to it but do not carry a trailing path along. The
    # diary feed hands the slug over for free; anything else resolves it once and keeps it.
    add_column :entries, :letterboxd_slug, :string
  end
end
