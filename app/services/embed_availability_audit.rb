# frozen_string_literal: true

# Finds the entries VidSrc cannot actually play -- the ones that frame up and say "This
# media is unavailable".
#
# Nothing about the embed URL says so. Every vidsrc front door answers 200 with the same
# shell whether or not there is a file behind it, which is why Entry#check_source, which
# reads the page title, calls these healthy.
#
# Two stages, because the honest check costs a request per title:
#
#   1. VidsrcCatalog screens the whole catalogue against the daily ID dumps, in three
#      requests. It is not accurate enough to report on -- one in eight of the entries it
#      calls missing turns out to be playable -- but it is accurate in the other direction,
#      so what it passes needs no further asking.
#   2. VidsrcAvailability confirms each entry the screen doubted, one request each, against
#      the API the player itself asks.
#
# So a sweep costs three requests plus one per suspect, rather than one per entry, and
# reports only what the authoritative source called missing.
#
# Read-only: it reports, and deliberately does not touch `stream`. That column carries
# somebody's judgement -- the "report broken link" button on every card -- and a sweep
# should not quietly overrule a person.
class EmbedAvailabilityAudit
  # Raised when the check cannot be trusted to run at all. Reporting nothing is the only
  # safe answer to that: if the dumps come back empty or the API stops responding, every
  # entry looks unplayable, and a sweep that believed it would condemn the whole catalogue.
  class CannotCheck < StandardError; end

  Row = Struct.new(:entry, :lookup, :reason, keyword_init: true)
  Result = Struct.new(:checked, :suspected, :missing, :unknown, :skipped, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(scope: Entry.all, catalog: VidsrcCatalog.new, availability: VidsrcAvailability.new, progress: nil)
    @scope = scope
    @catalog = catalog
    @availability = availability
    @progress = progress
  end

  def call
    prepare!

    checked = 0
    skipped = 0
    unknown = []
    suspects = []

    entries.each do |entry|
      lookup = @availability.lookup_for(entry)
      # No imdb id, or a series with no episode resolved: there is no question to ask
      # VidSrc about it. sources:audit is where that shows up.
      next skipped += 1 unless lookup.is_a?(VidsrcAvailability::Lookup)

      checked += 1
      suspects << [entry, lookup] unless in_catalog?(lookup)
    end

    missing = []
    suspects.each_with_index do |(entry, lookup), index|
      @progress&.call(index + 1, suspects.size)
      result = @availability.for_entry(entry)

      if result.missing?
        missing << Row.new(entry: entry, lookup: lookup, reason: result.detail)
      elsif result.unknown?
        unknown << Row.new(entry: entry, lookup: lookup, reason: result.detail)
      end
    end

    Result.new(checked: checked, suspected: suspects.size, missing: missing,
               unknown: unknown, skipped: skipped)
  end

  private

  # Both halves have to be working before a single entry is judged.
  def prepare!
    @catalog.warm!
    raise CannotCheck, 'the VidSrc data API is not answering' unless @availability.reachable?
  rescue VidsrcCatalog::Unavailable => e
    raise CannotCheck, "the VidSrc ID dumps could not be read: #{e.message}"
  end

  def in_catalog?(lookup)
    if lookup.type == 'movie'
      @catalog.movie?(lookup.imdb)
    else
      @catalog.episode?(lookup.imdb, lookup.season, lookup.episode)
    end
  end

  # Only entries that would actually play through VidSrc. A channel on Drive or YouTube is
  # not VidSrc's to answer for.
  def entries
    @scope.includes(:list, :provider, :current, :subentries).select do |entry|
      entry.resolved_source&.sync_adapter == 'vidsrc'
    end
  end
end
