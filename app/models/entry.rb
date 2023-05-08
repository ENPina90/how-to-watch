class Entry < ApplicationRecord
  belongs_to :list

  def self.genres
    Entry.all.group_by(&:genre).keys.map(&:split).flatten.map { |genre| genre.tr(',', '') }.uniq.sort
  end
end
