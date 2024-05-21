require 'csv'

class Entry < ApplicationRecord
  belongs_to :list
  validates :name, uniqueness: { scope: :list }

  include PgSearch::Model
  pg_search_scope :search_by_input,
                  against: %i[name franchise category writer actors genre director],
                  using: {
                    tsearch: {
                      prefix: true
                    }
                  }

  # after_create :check_source

  def self.create_from_source(entry, list, seen)
    Entry.create!(
      position: entry[:position] || (list.entries.empty? ? 1 : list.entries.last.position + 1),
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
      source: entry[:source] || "https://v2.vidsrc.me/embed/#{entry[:imdb]}",
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
    FailedEntry.create(name: entry["Title"], year: entry["Year"])
    message = "Failed to create movie entry: #{e}"
    Rails.logger.error(message)
    return message
  end

  def self.to_csv
    CsvExporterService.generate_csv(all)
  end

  def self.like(name)
    where('name ILIKE ?', "%#{name}%").first
  end

  def check_source
    update(stream: UrlCheckerService.new(source).valid_source?)
  end

  def streamable
    return if stream

    # update(source: '')
    errors.add(:source, "is unavailable, do you have an alternative?")
  end
end
