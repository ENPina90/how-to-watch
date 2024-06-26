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
      imdb:      subentry['imdbID'],
      rating:    subentry['imdbRating'].to_f,
    )
  rescue StandardError => e
    handle_creation_error(subentry, e)
  end

  def self.generate_source(imdb_id, season, episode)
    "https://v2.vidsrc.me/embed/#{imdb_id}/#{season}-#{episode}"
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
