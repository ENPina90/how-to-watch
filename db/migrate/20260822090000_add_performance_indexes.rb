class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Every list page orders entries by position within a list.
    add_index :entries, [:list_id, :position], if_not_exists: true
    # Lookups while importing and de-duplicating.
    add_index :entries, :imdb, if_not_exists: true
    # The partial picker and the provider template lookup both filter on media.
    add_index :entries, :media, if_not_exists: true
    # OmdbApi and the episode sidebar look subentries up by this triple.
    add_index :subentries, [:entry_id, :season, :episode], if_not_exists: true
    # Community lists on the index page filter other users' lists by privacy.
    add_index :lists, [:user_id, :private], if_not_exists: true
  end
end
