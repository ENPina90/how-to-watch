# frozen_string_literal: true

# A trailer for something in the catalogue, picked at random -- what /trailers and channel 0
# on /cable play, one after another.
#
# Read straight off `entries.trailer` rather than copied into a channel of its own. A copy
# would be fourteen hundred rows that go stale the moment a film's trailer is fetched again
# or a film is added, and watching a trailer is not watching the film: the per-user tables
# would record the wrong thing.
#
# Picked by video rather than by entry. The same film sits in several channels, each copy
# carrying the same trailer, and choosing among entries would play the popular films more
# often for no better reason than having been filed twice.
class TrailerReel
  # Every trailer the app has written is a watch link, which is what TmdbService builds; the
  # other two shapes are what a trailer pasted in by hand could be.
  YOUTUBE_ID = %r{(?:[?&]v=|youtu\.be/|/embed/)([\w-]{11})}

  # How many recent trailers a viewer is spared seeing again. Kept in the session, so it is
  # bounded by what a cookie can carry as much as by what is worth remembering: thirty is an
  # hour or so of trailers, and a little over three hundred bytes.
  REMEMBERED = 30

  # YouTube's own player options, belonging to this use rather than to the provider row:
  # play at once, stay on this channel's videos at the end rather than suggesting others,
  # and -- the one that matters -- report back, so the page can hear a trailer end or
  # refuse to play. See trailer_reel_controller.js.
  PLAYER_OPTIONS = {
    autoplay: 1, rel: 0, modestbranding: 1, playsinline: 1, iv_load_policy: 3, enablejsapi: 1
  }.freeze

  Trailer = Struct.new(:entry, :youtube_id, :embed_url, keyword_init: true)

  # The seen list with this trailer added to the end, a repeat moved rather than doubled.
  def self.remember(seen, youtube_id)
    (Array(seen) - [youtube_id] + [youtube_id]).last(REMEMBERED)
  end

  # `user` decides which private channels count: their own and nobody else's, and none at
  # all for a visitor with no account -- the same line refuse_guest_on_private! draws.
  def initialize(user:, seen: [])
    @user = user
    @seen = Array(seen).map(&:to_s)
  end

  # Nil when there is nothing to play: no trailers the viewer may see, or no YouTube
  # provider to build an embed from.
  def pick
    source = Source.find_by(slug: 'youtube', active: true)
    return nil if source.nil?

    by_video = candidates
    return nil if by_video.empty?

    youtube_id = choose(by_video.keys)
    entry = Entry.includes(:list).find_by(id: by_video[youtube_id])
    embed_url = embed_url_for(source, youtube_id)
    return nil if entry.nil? || embed_url.blank?

    Trailer.new(entry: entry, youtube_id: youtube_id, embed_url: embed_url)
  end

  private

  # Something not seen lately. Once everything has been, anything but the one just played --
  # a catalogue with two trailers should alternate rather than stick.
  def choose(ids)
    fresh = ids - @seen
    return fresh.sample if fresh.any?

    (ids - [@seen.last]).presence&.sample || ids.sample
  end

  # Video id -> the entry to link to, one entry per video. Plucked whole rather than asked
  # for one random row: the id lives inside a URL, so picking by video means reading them,
  # and it is two short columns across fifteen hundred rows. The lowest id wins a tie, which
  # is the channel the film was filed in first.
  def candidates
    visible.order(:id).pluck(:id, :trailer).each_with_object({}) do |(id, trailer), found|
      youtube_id = trailer.to_s[YOUTUBE_ID, 1]
      found[youtube_id] ||= id if youtube_id
    end
  end

  def visible
    with_trailer = Entry.joins(:list).where.not(trailer: [nil, ''])
    public_ones = with_trailer.where(lists: { private: [false, nil] })
    return public_ones if @user.nil?

    public_ones.or(with_trailer.where(lists: { user_id: @user.id }))
  end

  # On the YouTube provider's own template, as CommercialReel#embed_url does, so the domain
  # lives in the one row every other playback domain lives in.
  def embed_url_for(source, youtube_id)
    base = source.build_url('default', { source_key: youtube_id })
    return nil if base.blank?

    "#{base}#{base.include?('?') ? '&' : '?'}#{PLAYER_OPTIONS.to_query}"
  end
end
