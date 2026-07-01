# frozen_string_literal: true

# Idempotent seed for streaming providers. Run via `rails sources:seed`.
# Templates port the exact URL shapes from Entry.generate_source / generate_source_two
# and Subentry.generate_source so imdb-keyed URLs are byte-for-byte unchanged.
#
# Placeholders: %{imdb} %{series_imdb} %{season} %{episode} %{absolute_episode} %{source_key}
# For series/anime the resolver is passed the current subentry, so season/episode resolve.

SOURCES = [
  {
    slug: "vidsrc-cc", name: "VidSrc.cc", kind: "imdb",
    autoplay_param: "autoplay", position: 1,
    templates: {
      "movie"   => "https://vidsrc.cc/v3/embed/movie/%{imdb}",
      "series"  => "https://vidsrc.cc/v3/embed/tv/%{series_imdb}/%{season}/%{episode}",
      "episode" => "https://vidsrc.cc/v3/embed/tv/%{series_imdb}/%{season}/%{episode}",
      "anime"   => "https://vidsrc.cc/v2/embed/anime/%{series_imdb}/%{absolute_episode}/sub",
    },
  },
  {
    slug: "vidsrcme", name: "VidSrc.me", kind: "imdb",
    autoplay_param: "autoplay", position: 2,
    templates: {
      "movie"   => "https://v2.vidsrc.me/embed/%{imdb}",
      "series"  => "https://v2.vidsrc.me/embed/%{series_imdb}/%{season}-%{episode}",
      "episode" => "https://v2.vidsrc.me/embed/%{series_imdb}/%{season}-%{episode}",
      "anime"   => "https://v2.vidsrc.me/embed/%{series_imdb}/%{season}-%{episode}",
    },
  },
  {
    slug: "google-drive", name: "Google Drive", kind: "direct", position: 3,
    templates: { "default" => "https://drive.google.com/file/d/%{source_key}/preview" },
  },
  {
    slug: "mega", name: "MEGA", kind: "direct", position: 4,
    templates: { "default" => "https://mega.nz/embed/%{source_key}" },
  },
  {
    slug: "youtube", name: "YouTube", kind: "direct", position: 5,
    templates: { "default" => "https://www.youtube.com/embed/%{source_key}" },
  },
  {
    slug: "archive-org", name: "Internet Archive", kind: "direct", position: 6,
    templates: { "default" => "https://archive.org/embed/%{source_key}" },
  },
  {
    # Catch-all for heterogeneous one-off embeds (ok.ru, gotaku, anitaku, wikia, drive
    # folders, ...). source_key holds the full URL; template passes it through verbatim.
    slug: "custom", name: "Custom URL", kind: "direct", position: 99,
    templates: { "default" => "%{source_key}" },
  },
].freeze

SOURCES.each do |attrs|
  source = Source.find_or_initialize_by(slug: attrs[:slug])
  source.assign_attributes(attrs)
  source.save!
  puts "✅ #{source.slug} (#{source.kind})"
end

puts "Seeded #{Source.count} sources."
