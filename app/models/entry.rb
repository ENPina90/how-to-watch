require 'csv'

class Entry < ApplicationRecord
  belongs_to :list
  validates :name, presence: true, uniqueness: { scope: :list }

  include PgSearch::Model
  pg_search_scope :search_by_input,
                  against: %i[name franchise category writer actors genre director],
                  using: {
                    tsearch: {
                      prefix: true
                    }
                  }

  after_create :check_source

  # rubocop:disable Metrics/MethodLength
  def self.create_from_source(entry, list, seen)
    Entry.create!(
      position: entry[:position] || next_position(list),
      franchise: entry[:franchise],
      media: entry[:media],
      season: entry[:season],
      episode: entry[:episode],
      completed: seen,
      name: entry[:name],
      category: entry[:category],
      length: entry[:length],
      year: entry[:year],
      plot: entry[:plot],
      pic: entry[:pic],
      source: entry[:source] || generate_source(entry[:imdb]),
      genre: entry[:genre],
      director: entry[:director],
      writer: entry[:writer],
      actors: entry[:actors],
      rating: entry[:rating],
      language: entry[:language],
      note: entry[:note],
      list:
    )
  rescue StandardError => e
    handle_creation_error(entry, e)
  end
  # rubocop:enable Metrics/MethodLength

  def self.next_position(list)
    list.entries.empty? ? 1 : list.entries.last.position + 1
  end

  def self.generate_source(imdb_id)
    "https://v2.vidsrc.me/embed/#{imdb_id}"
  end

  def self.handle_creation_error(entry, error)
    FailedEntry.create(name: entry[:name], year: entry[:year])
    message = "Failed to create movie entry: #{error.message}"
    Rails.logger.error(message)
    message
  end

  def self.to_csv
    CsvExporterService.generate_seed_csv
  end

  def self.like(name)
    where('name ILIKE ?', "%#{name}%").first
  end

  def check_source
    update(stream: UrlCheckerService.new(source).valid_source?)
  end

  def streamable
    return if stream

    errors.add(:source, "is unavailable, do you have an alternative?")
  end
end
