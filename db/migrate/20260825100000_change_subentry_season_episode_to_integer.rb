# season/episode were stored as strings, so every ordering and comparison had to go
# through CAST(NULLIF(col, '') AS INTEGER) -- six sites, easy to forget, and it defeats
# the index. Checked before writing this: production holds no non-numeric values, 4 empty
# strings (which become NULL), and ranges well inside integer.
class ChangeSubentrySeasonEpisodeToInteger < ActiveRecord::Migration[8.0]
  def up
    change_column :subentries, :season, :integer, using: "NULLIF(season, '')::integer"
    change_column :subentries, :episode, :integer, using: "NULLIF(episode, '')::integer"
  end

  def down
    change_column :subentries, :season, :string
    change_column :subentries, :episode, :string
  end
end
