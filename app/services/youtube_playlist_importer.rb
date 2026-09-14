# frozen_string_literal: true

# Files a YouTube playlist into a channel: one entry per video, playing through the YouTube
# provider with the video id as its source_key.
#
# One entry per video rather than one series with a subentry per video. A provider template
# reads source_key off the entry (Source#url_for) and subentries have no source_key of their
# own, so a series built that way could only ever play one of its videos. Standalone
# `episode` entries are how the channels already made of YouTube uploads are laid out.
#
# Runs inside the request for the reason EntryCsvImporter does -- whoever pasted the link is
# told what became of every video while still looking at the page -- and is safe to run
# again: a video already in the channel is left alone, so importing a playlist that has grown
# since adds only what is new.
class YoutubePlaylistImporter
  # The only place a playlist says which episode a video is, and only by convention, in the
  # title. These are the shapes channels use: "S1 EP1", "S8 Ep9:", "S01E02", "Season 2
  # Episode 10". A title matching none of them is a video rather than an episode.
  EPISODE_NUMBER = /\b(?:S|Season\s*)(\d{1,2})\s*[-.:,]?\s*(?:Episode\s*|EP?\s*)(\d{1,3})\b/i

  Result = Struct.new(:title, :created, :notes, keyword_init: true) do
    def summary
      added = "#{created.size} #{'video'.pluralize(created.size)} added"
      title.present? ? "#{added} from #{title}" : added
    end

    def any_notes? = notes.any?
  end

  def initialize(url:, list:)
    @url = url
    @list = list
    @created = []
    @notes = []
  end

  def call
    # Asked before YouTube is: without the provider row there is no embed address to build,
    # and a channel of entries that cannot play is worse than no import.
    source = Source.find_by(slug: 'youtube', active: true)
    return failure('There is no active YouTube provider to play the videos through — add one on the Sources page') if source.nil?

    playlist = YoutubePlaylist.fetch(@url)
    import(playlist, source)

    Result.new(title: playlist.title, created: @created, notes: @notes)
  rescue YoutubePlaylist::RequestError => e
    failure(e.message)
  end

  private

  def import(playlist, source)
    present = ids_in_channel(source)
    position = Entry.next_position(@list)
    already = 0
    refused = []
    age_restricted = []

    playlist.videos.each do |video|
      if present.include?(video.youtube_id)
        already += 1
      elsif !video.playable?
        refused << video.title
      elsif create(playlist, video, source, position)
        position += 1
        age_restricted << video.title if video.age_restricted
      end
    end

    note_counts(playlist, already, refused, age_restricted)
  end

  # Matched on the first eleven characters because ids pasted from a share link by hand carry
  # YouTube's `?si=` tracking parameter along with them, and those are the same video.
  def ids_in_channel(source)
    @list.entries.where(provider: source).pluck(:source_key)
         .filter_map { |key| key.to_s[/\A[\w-]{11}/] }
         .to_set
  end

  def create(playlist, video, source, position)
    entry = @list.entries.new(attributes_for(playlist, video).merge(provider: source,
                                                                    source_key: video.youtube_id,
                                                                    position: position))
    if entry.save
      @created << entry
      entry
    else
      @notes << "#{video.title} — #{entry.errors.full_messages.to_sentence}"
      nil
    end
  rescue StandardError => e
    Rails.logger.error "YouTube import failed on #{video.youtube_id} for list #{@list.id}: #{e.class}: #{e.message}"
    @notes << "#{video.title} — #{e.message}"
    nil
  end

  def attributes_for(playlist, video)
    season, episode = video.title.match(EPISODE_NUMBER)&.captures&.map(&:to_i)

    {
      name: video.title,
      # `fanedit` for the rest because it is what this page files anything with no id behind
      # it as, and it is a card that does not print an empty S/E.
      media: episode ? 'episode' : 'fanedit',
      # The playlist is the only name the show has here. An episode's card and the channel's
      # grouping both read it, and it is one edit to correct.
      series: episode ? playlist.title : nil,
      season: season,
      episode: episode,
      category: playlist.title,
      length: minutes_in(video.duration_seconds),
      # When it went up on YouTube, which for a re-upload is not when it first aired. It is
      # the only date a video carries.
      year: video.published_at&.year,
      plot: synopsis_in(video.description),
      pic: video.thumbnail_url
    }
  end

  # Minutes, as everywhere else `length` is read -- the cable schedule, the watch page's
  # completion mark. Never rounded down to zero, which the schedule would take for no runtime.
  def minutes_in(seconds)
    seconds && [(seconds / 60.0).round, 1].max
  end

  # The first paragraph. What follows it in a channel's descriptions is links, sponsors and
  # "subscribe", which is not a plot.
  def synopsis_in(description)
    description.to_s.split(/\n\s*\n/).first.to_s.strip.presence
  end

  def note_counts(playlist, already, refused, age_restricted)
    @notes << "#{already} already in #{@list.name}" if already.positive?

    if playlist.unavailable.positive?
      @notes << "#{playlist.unavailable} private or deleted #{'video'.pluralize(playlist.unavailable)} left out"
    end

    @notes << "Not added, because embedding is switched off for them: #{refused.join(', ')}" if refused.any?
    return if age_restricted.empty?

    @notes << "Age-restricted, so YouTube may only play them on youtube.com: #{age_restricted.join(', ')}"
  end

  def failure(message) = Result.new(title: nil, created: [], notes: [message])
end
