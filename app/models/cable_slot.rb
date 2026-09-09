# frozen_string_literal: true

# One programme in one channel's day. See the migration for why the schedule is rows.
#
# Everything here is the same for every viewer. A slot knows what is playing and when it
# started; how far into it you are is a question about the clock, not about you.
class CableSlot < ApplicationRecord
  belongs_to :list
  belongs_to :entry
  belongs_to :subentry, optional: true
  # The adverts that fill the gap between this programme and the next. Optional twice over:
  # a slot whose film ends exactly on the five-minute mark has no gap, and a period we hold
  # no reel for has a gap with nothing to put in it.
  belongs_to :break_reel, class_name: "CommercialReel", optional: true

  # The row covering an instant. Half-open at the end so the moment one programme ends is
  # the moment the next begins, and never both.
  scope :on_air_at, lambda { |time|
    where(starts_at: ..time).where(arel_table[:ends_at].gt(time))
  }

  scope :in_order, -> { order(:starts_at) }

  # What the channel plays next, after a given moment.
  scope :after, ->(time) { where(arel_table[:starts_at].gteq(time)) }

  def duration = (ends_at - starts_at).to_i

  # The slot runs past the film, to the next five-minute mark. These two are the film's own
  # span; `duration` and `ends_at` are the slot's, which is what the listing shows.
  def programme_ends_at = break_starts_at || ends_at

  def programme_duration = (programme_ends_at - starts_at).to_i

  def break? = break_starts_at.present?

  # Is the channel in its commercial break at this moment?
  def break_at?(time) = break? && time >= break_starts_at

  # Where in the reel the break has reached. Counted from the moment the break began rather
  # than from when this viewer arrived, so everybody watching is at the same advert.
  #
  # A slot with no scheduled gap can still need adverts -- the film may end before the
  # catalogue said it would -- and there is no such moment to count from then, so the reel
  # simply starts where it was told to. Still the same point for everybody, which is what
  # matters; it just does not creep forward with the clock.
  def reel_position_at(time)
    return nil unless break_reel

    started = break_starts_at || ends_at

    break_offset.to_i + [(time - started).to_i, 0].max
  end

  # The next moment this channel shows something different: the start of the break, or the
  # start of the next programme. What the page sets its timer by.
  def next_change_after(time)
    return break_starts_at if break? && time < break_starts_at

    ends_at
  end

  # How far into the programme somebody turning on now has arrived. Clamped at both ends:
  # before it starts is the beginning, and a request that lands a hair past the end -- a
  # timer firing a moment early, a slow page -- is not asked to seek past the credits.
  def offset_at(time)
    [[(time - starts_at).to_i, 0].max, programme_duration].min
  end

  # A programme runs until it ends. This is what the page sets its timer by.
  def remaining_at(time) = [(ends_at - time).to_i, 0].max
end
