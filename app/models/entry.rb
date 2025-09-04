# frozen_string_literal: true

require 'csv'
require 'net/http'
require 'json'


class Entry < ApplicationRecord
  belongs_to :list
  has_one_attached :poster
  has_many :subentries, dependent: :destroy
  belongs_to :current, class_name: 'Subentry', optional: true, dependent: :destroy
  # has_many :current_list_users, class_name: 'ListUserEntries', foreign_key: 'current_entry_id'
  validates :name, presence: true, uniqueness: { scope: [:list, :series] }
  validates :media, presence: true

  accepts_nested_attributes_for :subentries, allow_destroy: true

  include PgSearch::Model
  pg_search_scope :search_by_input,
                  against: %i[name franchise category writer actors genre director],
                  using:   {
                    tsearch: {
                      prefix: true,
                    },
                  }

  after_create :check_source

  def self.create_from_source(entry, list, seen)
    puts "Normalizing data"
    entry = OmdbApi.normalize_omdb_data(entry) unless entry[:seed]
    puts "Createing Entry"
    Entry.create!(
      position:     entry[:position] || next_position(list),
      franchise:    entry[:franchise],
      media:        entry[:media],
      season:       entry[:season],
      episode:      entry[:episode],
      completed:    seen,
      name:         entry[:name],
      tmdb:         entry[:tmdb],
      imdb:         entry[:imdb],
      series_imdb:  entry[:series_imdb],
      trailer:      entry[:trailer],
      series:       entry[:series],
      category:     entry[:series],
      length:       entry[:length],
      year:         entry[:year],
      plot:         entry[:plot],
      pic:          entry[:pic],
      source:       entry[:source] || generate_source(entry) || generate_source(entry),
      genre:        entry[:genre],
      director:     entry[:director],
      writer:       entry[:writer],
      actors:       entry[:actors],
      rating:       entry[:rating],
      language:     entry[:language],
      note:         entry[:note],
      list:         list,
    )
  rescue StandardError => e
    handle_creation_error(entry, e)
  end

  def self.next_position(list)
    list.entries.empty? ? 1 : list.entries.maximum(:position) + 1
  end

  def self.generate_source(entry)
    if entry[:media] == "episode"
    "https://v2.vidsrc.me/embed/#{entry[:series_imdb]}/#{entry[:season]}-#{entry[:episode]}"
    else
    "https://v2.vidsrc.me/embed/#{entry[:imdb]}"
    end
  end

  def self.handle_creation_error(entry, error)
    FailedEntry.create(name: entry[:name] || entry['Title'], year: entry[:year] || entry['Year'])
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

  def set_current(change)
    subentries = self.subentries.order(:season)
    index = subentries.index(self.current) || -1
    self.update(current: subentries[index + change])
  end

  def next
    list.entries.where('position > ?', position).order(:position).first
  end

  def previous
    list.entries.where('position < ?', position).order(:position).last
  end

  def complete(boolean)
    self.update(completed: boolean)
    self.list.watched!
    completed
  end

  def streamable
    return if stream

    errors.add(:source, 'is unavailable, do you have an alternative?')
  end

  # Check if the entry's image URL is valid
  def image_valid?
    return false if pic.blank?
    TmdbService.new.validate_image_url(pic)
  end

  # Repair the entry's image if it's broken
  def repair_image!
    ImageRepairService.new.repair_entry_image(self)
  end
end
