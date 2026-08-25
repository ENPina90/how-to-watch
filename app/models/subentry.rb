class Subentry < ApplicationRecord
  belongs_to :entry
  # A user's saved position points here. Without this, destroying a subentry (on its
  # own, or via the parent entry's cascade) violates the current_subentry_id FK.
  has_many :user_entry_positions, foreign_key: :current_subentry_id,
                                  inverse_of: :current_subentry, dependent: :nullify
  validates :episode, uniqueness: { scope: [:season, :entry_id], message: "season and episode combination must be unique within the same entry" }

  before_destroy :nullify_current_entries


  def self.create_from_source(main_entry, subentry, season, seen: false)
    Subentry.create!(
      entry:     main_entry,
      season:    season,
      episode:   subentry['Episode'],
      completed: seen,
      name:      subentry['Title'],
      plot:      subentry['Plot'] || subentry['overview'], # Support both OMDB and TMDB data
      imdb:      subentry['imdbID'],
      rating:    subentry['imdbRating'].to_f,
    )
  rescue StandardError => e
    handle_creation_error(subentry, e)
  end

  # Calculate absolute episode number for anime (episodes are numbered continuously across seasons)
  def calculate_absolute_episode_number
    return episode.to_i if season.to_i <= 1

    # Count all episodes in previous seasons
    previous_episodes = entry.subentries.where('season < ?', season).count

    previous_episodes + episode.to_i
  end

  def self.handle_creation_error(entry, error)
    FailedEntry.create(name: entry[:name] || entry['Title'], year: entry[:year] || entry['Year'])
    message = "Failed to create movie entry: #{error.message}"
    Rails.logger.error(message)
    message
  end

  private

  def nullify_current_entries
    entry = self.entry
    siblings = entry.subentries.order(:season, :episode)
    index = siblings.index(self)
    next_entry = index == 0 ? nil : siblings[index - 1].id
    entry.update(current_id: next_entry)
  end
end
