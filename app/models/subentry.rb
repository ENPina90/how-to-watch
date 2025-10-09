class Subentry < ApplicationRecord
  belongs_to :entry
  validates :episode, uniqueness: { scope: [:season, :entry_id], message: "season and episode combination must be unique within the same entry" }

  before_destroy :nullify_current_entries


  def self.create_from_source(main_entry, subentry, season, seen: false)
    Subentry.create!(
      entry:     main_entry,
      season:    season,
      episode:   subentry['Episode'],
      completed: seen,
      source:    generate_source(subentry[:imdb], subentry[:season], subentry[:episode]),
      name:      subentry['Title'],
      plot:      subentry['Plot'] || subentry['overview'], # Support both OMDB and TMDB data
      imdb:      subentry['imdbID'],
      rating:    subentry['imdbRating'].to_f,
    )
  rescue StandardError => e
    handle_creation_error(subentry, e)
  end

  def self.generate_source(imdb_id, season, episode)
    "https://v2.vidsrc.me/embed/#{imdb_id}/#{season}-#{episode}"
  end

  # Fix malformed source URLs for existing subentries
  def fix_source_url!(force: false)
    # Check if source needs fixing
    needs_fix = source.blank? || source.include?('//-')

    # For anime, also fix if it's missing /sub at the end or has season/episode format
    if entry.media == 'anime' && source.present?
      needs_fix = true if source.match?(/anime\/[^\/]+\/\d+\/\d+/) # Has season/episode format
      needs_fix = true unless source.end_with?('/sub') # Missing /sub suffix
    end

    return unless needs_fix || force

    # Get the parent entry's IMDB or series_imdb
    series_imdb = entry.series_imdb || entry.imdb

    if series_imdb.present? && episode.present?
      # Determine correct source based on entry media type
      new_source = if entry.media == 'anime'
        # Anime uses absolute episode numbers across all seasons, with /sub at the end
        absolute_episode = calculate_absolute_episode_number
        "https://vidsrc.cc/v2/embed/anime/#{series_imdb}/#{absolute_episode}/sub"
      else
        "https://vidsrc.cc/v3/embed/tv/#{series_imdb}/#{season}/#{episode}"
      end

      update!(source: new_source)
      Rails.logger.info "Fixed source for subentry #{id}: #{new_source}"
    else
      Rails.logger.error "Cannot fix source for subentry #{id}: missing data"
    end
  end

  # Calculate absolute episode number for anime (episodes are numbered continuously across seasons)
  def calculate_absolute_episode_number
    return episode.to_i if season.to_i <= 1

    # Count all episodes in previous seasons
    previous_episodes = entry.subentries
                             .where('CAST(NULLIF(season, \'\') AS INTEGER) < ?', season.to_i)
                             .count

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
