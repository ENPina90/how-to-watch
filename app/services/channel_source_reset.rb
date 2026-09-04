# frozen_string_literal: true

# Points every channel at one streaming provider in a single pass.
#
# Two things make this more than a one-line update.
#
# An entry's own provider beats its channel's (see Entry#resolved_source), so a reset that
# touched only channels would quietly miss every entry carrying an override. Those are
# cleared rather than repointed, so from here on they inherit whatever their channel is set
# to -- which also means the next reset reaches them without special handling.
#
# And a direct provider is not interchangeable with anything. MEGA, Drive, YouTube and the
# rest address a file by a source_key that means nothing to any other provider, so moving
# one produces a dead link rather than a different player. Everything on a direct provider,
# channel or entry, is left exactly as it is. Only imdb providers move: they address a film
# by an id all of them understand, which is what makes them swappable in the first place.
class ChannelSourceReset
  class NotAnImdbSource < ArgumentError; end

  Result = Struct.new(:channels, :entries, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(source)
    @source = source
  end

  def call
    raise NotAnImdbSource, "#{source.slug} is a #{source.kind} provider" unless source.imdb?

    ActiveRecord::Base.transaction do
      Result.new(channels: point_channels, entries: clear_entry_overrides)
    end
  end

  private

  attr_reader :source

  # Channels with no provider are included: they are currently falling through to whichever
  # active provider sorts first, which is a default nobody chose. Naming it is the point.
  def point_channels
    List.where(provider_id: [nil, *imdb_source_ids])
        .update_all(provider_id: source.id, updated_at: Time.current)
  end

  def clear_entry_overrides
    Entry.where(provider_id: imdb_source_ids)
         .update_all(provider_id: nil, updated_at: Time.current)
  end

  # Deactivated imdb providers are deliberately in here. A channel stranded on one is
  # exactly what this is for -- it is the case that sends a channel to the fallback.
  def imdb_source_ids
    @imdb_source_ids ||= Source.where(kind: 'imdb').pluck(:id)
  end
end
