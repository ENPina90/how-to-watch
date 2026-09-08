# frozen_string_literal: true

# A compilation of period adverts, for filling the gap between programmes.
#
# One per year for the years that have one, and one per era for the stretches that do not.
# Matched against the year of the film that has just finished, so a 1987 film goes out to
# 1987 adverts -- which is most of what makes a break feel like it belongs to the channel
# rather than to the internet.
class CommercialReel < ApplicationRecord
  validates :label, :youtube_id, presence: true
  validates :youtube_id, uniqueness: true
  validates :starts_year, :ends_year, presence: true, numericality: { only_integer: true }
  validate :years_run_forwards

  scope :covering, ->(year) { where(starts_year: ..year).where(ends_year: year..) }
  scope :in_order, -> { order(:starts_year) }

  # How far into a reel a break may begin when its runtime is unknown. Every one of these is
  # a quarter of an hour at the very least, so anywhere in the first five minutes is safe
  # without knowing anything more -- and knowing more only widens it.
  BLIND_WINDOW = 5.minutes

  # The reel for a film of this year. Falls to the nearest era at either end rather than to
  # nothing: a 1928 film gets the oldest adverts we have, which is a better answer than a
  # blank screen and is what a channel with a tape library would do.
  def self.for_year(year)
    return nil if none? || count.zero?

    year = year.to_i
    covering(year).order("RANDOM()").first || nearest(year)
  end

  def self.nearest(year)
    return in_order.first if year < (minimum(:starts_year) || 0)

    in_order.last
  end

  # Where in the reel a break of this length may start. Never so late that the reel would
  # run out mid-break -- there is no third thing to cut to.
  def random_offset_for(seconds)
    room = usable_length - seconds
    return 0 if room <= 0

    rand(0..room.to_i)
  end

  def usable_length
    duration_seconds.to_i.positive? ? duration_seconds : BLIND_WINDOW.to_i
  end

  # The embed, built on the YouTube provider's own template so that the domain lives where
  # every other playback domain in this app lives -- one row to edit if YouTube ever moves
  # embedding somewhere else. The player options after it are YouTube's own and belong to
  # this use rather than to the provider: start part-way in, play at once, and no chrome,
  # because nobody is meant to drive a commercial break.
  def embed_url(start_at: 0)
    # The vars hash is positional, and braces are required: `source_key: youtube_id` on its
    # own is read as keyword arguments, which build_url also takes.
    base = Source.find_by(slug: "youtube", active: true)&.build_url("default", { source_key: youtube_id })
    return nil if base.blank?

    options = {
      autoplay: 1, start: start_at.to_i, controls: 0, disablekb: 1,
      modestbranding: 1, rel: 0, playsinline: 1, iv_load_policy: 3,
      # So the page can hear the player refuse. A YouTube embed that will not play says so
      # only to whoever asked it to listen -- everyone else gets a black rectangle reading
      # "This video is unavailable" for the length of the break. See cable_filler.
      enablejsapi: 1
    }
    "#{base}#{base.include?('?') ? '&' : '?'}#{options.to_query}"
  end

  private

  def years_run_forwards
    return if starts_year.blank? || ends_year.blank? || ends_year >= starts_year

    errors.add(:ends_year, "must not be before the first year")
  end
end
