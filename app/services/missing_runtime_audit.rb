# frozen_string_literal: true

# Finds the entries the cable schedule has to guess a length for.
#
# `entries.length` is the catalogue's claim about how long something runs, and it is what
# CableSchedule lays a day out from. Where it is missing the schedule falls back to a flat
# guess -- a hundred minutes for a film, thirty for anything else -- and a guess that
# overshoots the real file is not harmless: the slot outlasts the video, and the player,
# handed a start position past the end, silently starts the whole thing again. That is the
# fault this exists to make visible before somebody runs into it.
#
# Only what is on the dial. A missing runtime anywhere else is untidy; a missing runtime on
# a channel that plays to a clock is a programme that will misbehave, and the difference
# between the two is the difference between twenty-two entries somebody can work through
# and four hundred and fifty-seven they never will. Widen `scope` to sweep the lot.
class MissingRuntimeAudit
  Row = Struct.new(:entry, :channel, keyword_init: true)
  Result = Struct.new(:checked, :missing, keyword_init: true)

  def self.call(...) = new(...).call

  # Every entry the dial can reach, including what a channel borrows from the channels
  # inside it -- the schedule draws from the same sequence, so this must too.
  def self.scheduled
    CableSchedule.channels.flat_map do |channel|
      channel.watch_sequence.map { |entry| Row.new(entry: entry, channel: channel) }
    end
  end

  def initialize(scope: self.class.scheduled)
    @scope = scope
  end

  def call
    # An entry borrowed by two channels is one problem, not two. The first channel that
    # reaches it is the one the notification names.
    rows = @scope.uniq { |row| row.entry.id }

    Result.new(checked: rows.size, missing: rows.select { |row| row.entry.length.to_i.zero? })
  end
end
