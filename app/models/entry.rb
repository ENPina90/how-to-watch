# frozen_string_literal: true

require 'csv'

class Entry < ApplicationRecord

  belongs_to :list
  has_many :subentries, dependent: :destroy
  belongs_to :current, class_name: 'Subentry', optional: true, dependent: :destroy
  # has_many :current_list_users, class_name: 'ListUserEntries', foreign_key: 'current_entry_id'
  validates :name, presence: true, uniqueness: { scope: :list }

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
    entry = OmdbApi.normalize_omdb_data(entry) unless entry[:seed]
    Entry.create!(
      position:  entry[:position] || next_position(list),
      franchise: entry[:franchise],
      media:     entry[:media],
      season:    entry[:season],
      episode:   entry[:episode],
      completed: seen,
      name:      entry[:name],
      imdb:      entry[:imdb],
      series:    entry[:series],
      length:    entry[:length],
      year:      entry[:year],
      plot:      entry[:plot],
      pic:       entry[:pic],
      source:    entry[:source] || generate_source(entry[:imdb]),
      genre:     entry[:genre],
      director:  entry[:director],
      writer:    entry[:writer],
      actors:    entry[:actors],
      rating:    entry[:rating],
      language:  entry[:language],
      note:      entry[:note],
      list:      list,
    )
  rescue StandardError => e
    handle_creation_error(entry, e)
  end

  def self.next_position(list)
    list.entries.empty? ? 1 : list.entries.last.position + 1
  end

  def self.generate_source(imdb_id)
    "https://v2.vidsrc.me/embed/#{imdb_id}"
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
    completed
  end

  def streamable
    return if stream

    errors.add(:source, 'is unavailable, do you have an alternative?')
  end

end
