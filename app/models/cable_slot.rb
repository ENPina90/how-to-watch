# frozen_string_literal: true

# One programme in one channel's day. See the migration for why the schedule is rows.
#
# Everything here is the same for every viewer. A slot knows what is playing and when it
# started; how far into it you are is a question about the clock, not about you.
class CableSlot < ApplicationRecord
  belongs_to :list
  belongs_to :entry
  belongs_to :subentry, optional: true

  # The row covering an instant. Half-open at the end so the moment one programme ends is
  # the moment the next begins, and never both.
  scope :on_air_at, lambda { |time|
    where(starts_at: ..time).where(arel_table[:ends_at].gt(time))
  }

  scope :in_order, -> { order(:starts_at) }

  # What the channel plays next, after a given moment.
  scope :after, ->(time) { where(arel_table[:starts_at].gteq(time)) }

  def duration = (ends_at - starts_at).to_i

  # How far into the programme somebody turning on now has arrived. Clamped at both ends:
  # before it starts is the beginning, and a request that lands a hair past the end -- a
  # timer firing a moment early, a slow page -- is not asked to seek past the credits.
  def offset_at(time)
    [[(time - starts_at).to_i, 0].max, duration].min
  end

  # A programme runs until it ends. This is what the page sets its timer by.
  def remaining_at(time) = [(ends_at - time).to_i, 0].max
end
