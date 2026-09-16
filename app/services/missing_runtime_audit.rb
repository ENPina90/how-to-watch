# frozen_string_literal: true

# Finds the entries with no runtime recorded.
#
# `entries.length` is the catalogue's claim about how long something runs, and it is what
# CableSchedule lays a day out from. Where it is missing the schedule falls back to a flat
# guess -- a hundred minutes for a film, thirty for anything else -- and a guess that
# overshoots the real file is not harmless: the slot outlasts the video, and the player,
# handed a start position past the end, silently starts the whole thing again. That is the
# fault this exists to make visible before somebody runs into it.
#
# It sweeps the whole catalogue rather than only the dial. The harm above is what a blank
# runtime does once something schedules it, and an entry goes onto a channel long after it
# was added -- so the time worth hearing about it is before that, not the week it
# misbehaves. What is already on a clock is still marked: `Row#channel` names the channel
# that reaches an entry, and is nil for everything nothing schedules yet.
class MissingRuntimeAudit
  Row = Struct.new(:entry, :channel, keyword_init: true)
  Result = Struct.new(:checked, :missing, keyword_init: true)

  def self.call(...) = new(...).call

  # Every entry, with what decides the question loaded up front: `guessed_at?` reads each
  # entry's episodes, and asking per entry is a query apiece across the whole catalogue.
  def self.everything
    dial = dial_channels
    rows = []

    Entry.includes(:subentries, :list).find_each(batch_size: 500) do |entry|
      rows << Row.new(entry: entry, channel: dial[entry.id])
    end

    rows
  end

  # Every entry the dial can reach, including what a channel borrows from the channels
  # inside it -- the schedule draws from the same sequence, so this must too. Still a scope
  # in its own right: it is the answer to "what is at risk right now", one argument away.
  def self.scheduled
    CableSchedule.channels.flat_map do |channel|
      channel.watch_sequence.map { |entry| Row.new(entry: entry, channel: channel) }
    end
  end

  # Which channel to name for an entry that is on the dial. The first that reaches it wins:
  # an entry borrowed by two channels is one problem, not two.
  def self.dial_channels
    scheduled.each_with_object({}) { |row, acc| acc[row.entry.id] ||= row.channel }
  end

  def initialize(scope: self.class.everything)
    @scope = scope
  end

  def call
    rows = @scope.uniq { |row| row.entry.id }

    Result.new(checked: rows.size, missing: rows.select { |row| guessed_at?(row.entry) })
  end

  # Would the schedule have to guess for this entry?
  #
  # Not simply "has no runtime of its own". A show does not have a runtime -- its episodes
  # do, and the schedule lays each slot out by whichever episode it picked. So a series
  # whose episodes all carry one needs no guess, however blank the show itself is, and a
  # series with even one bare episode does whenever that episode comes up.
  #
  # Asked of the loaded records rather than in SQL, because `everything` has preloaded them
  # and a `where` here would go back to the database once per entry in the catalogue.
  def guessed_at?(entry)
    episodes = entry.subentries
    return episodes.any? { |episode| episode.length.to_i.zero? } if episodes.any?

    entry.length.to_i.zero?
  end
end
