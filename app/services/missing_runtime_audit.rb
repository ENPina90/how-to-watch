# frozen_string_literal: true

# Finds the entries with no runtime recorded.
#
# `entries.length` is the catalogue's claim about how long something runs, and it is what
# CableSchedule lays a day out from. Where it is missing -- for a show, where an episode's is
# -- the schedule leaves that programme out entirely rather than guess (CableSchedule::
# MIN_MINUTES says why). So a blank runtime is a film, or an episode, quietly missing from
# every channel it is on, and nobody would notice it had gone. That is what this exists to
# make visible.
#
# What it calls missing is narrower than what the schedule leaves out. Cable will not pin
# anything under CableSchedule::MIN_MINUTES to the clock, but a three-minute YouTube video
# really is three minutes long, and a warning about it is one nobody can act on. So the
# sweep only complains about a runtime that is plainly not a runtime -- see BARE_MINUTES.
#
# It sweeps the whole catalogue rather than only the dial, because an entry goes onto a
# channel long after it was added and the time worth hearing about it is before then. What
# is already on a channel is still marked: `Row#channel` names the channel that reaches an
# entry, and is nil for everything nothing schedules yet.
class MissingRuntimeAudit
  Row = Struct.new(:entry, :channel, keyword_init: true)
  Result = Struct.new(:checked, :missing, keyword_init: true)

  # At or below this, a runtime is taken to be absent rather than short: nil, zero, or the
  # single minute OMDB and a rounded-up importer produce when they have nothing better. Two
  # minutes and up is believed, however far under the schedule's own floor it falls.
  BARE_MINUTES = 1

  # Is this runtime missing, as far as a warning goes? Shared with the notifier's episode
  # count so the card and the sweep cannot disagree about which episodes are bare.
  def self.bare?(minutes) = minutes.to_i <= BARE_MINUTES

  def self.call(...) = new(...).call

  # Every entry, with what decides the question loaded up front: `untimed?` reads each
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

    Result.new(checked: rows.size, missing: rows.select { |row| untimed?(row.entry) })
  end

  # Is any of this entry held off the schedule for want of a runtime?
  #
  # Not simply "has no runtime of its own". A show does not have a runtime -- its episodes
  # do, and the schedule times each slot by whichever episode it picked. So a series whose
  # episodes all carry one is complete, however blank the show itself is, and a series with
  # even one bare episode is missing that episode from the air. Each episode's figure comes
  # from Entry#runtime_minutes, the one the schedule reads too.
  #
  # A show with no episodes at all falls through to the show's own figure. Cable cannot air
  # it either way, but a blank one there is the sign nothing was ever imported for it.
  #
  # Asked of the loaded records rather than in SQL, because `everything` has preloaded them
  # and a `where` here would go back to the database once per entry in the catalogue.
  def untimed?(entry)
    episodes = entry.subentries
    return episodes.any? { |episode| self.class.bare?(entry.runtime_minutes(episode)) } if episodes.any?

    self.class.bare?(entry.length)
  end
end
