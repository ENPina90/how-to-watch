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

  after_create :check_source

  def self.create_from_OMDB(result, list, seen)
    Entry.create!(
      media: result["Type"],
      source: "https://v2.vidsrc.me/embed/#{result["imdbID"]}",
      name: result["Title"],
      alt: result["alt"],
      year: result["Year"].to_i,
      pic: result["Poster"],
      genre: result["Genre"],
      director: result["Director"],
      writer: result["Writer"],
      actors: result["Actors"],
      plot: result["Plot"],
      rating: result["imdbRating"].to_f,
      length: result["Runtime"].split(" ")[0].to_i,
      language: result["Language"],
      position: result["position"],
      episode: result["episode"],
      season: result["season"],
      category: result['category'],
      completed: seen == "TRUE",
      list: list
    )
  rescue StandardError => e
    FailedEntry.create(name: result["Title"], year: result["Year"])
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
