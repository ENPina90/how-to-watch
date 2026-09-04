# frozen_string_literal: true

# Baseline streaming providers. Run manually via `rails sources:seed` -- nothing
# loads this at boot, so editing it does not change an already-seeded database.
#
# CREATE-ONLY: existing rows are never modified, so admin edits made through the UI
# (activating/deactivating a provider, tweaking a template) survive deploys. To change
# an existing provider, edit it in the UI; only brand-new slugs here get created.
#
# Placeholders: %{imdb} %{series_imdb} %{season} %{episode} %{absolute_episode} %{source_key}
# For series/anime the resolver is passed the current subentry; standalone episode
# entries resolve season/episode from the entry itself.

SOURCES = [
  {
    # Primary imdb provider. vidsrc2.ru and vidsrc.ir are the two domains the provider
    # told everyone to move to on 2026-08-30, when it said its registrar had stopped
    # answering for the older ones. See docs/guides/VIDSRC.md §1.
    slug: "vidsrc2", name: "VidSrc 2", kind: "imdb",
    autoplay_param: "autoplay", position: 1, active: true,
    templates: {
      "movie"   => "https://vidsrc2.ru/embed/movie?imdb=%{imdb}&ds_lang=en",
      "series"  => "https://vidsrc2.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en",
      "episode" => "https://vidsrc2.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en",
      # vidsrc has no anime-specific endpoint; anime plays through the tv one.
      "anime"   => "https://vidsrc2.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en",
    },
  },
  {
    # Same backend as vidsrc2.ru, different front door -- kept as the immediate fallback
    # for when one of the two domains goes down.
    slug: "vidsrc-ir", name: "VidSrc IR", kind: "imdb",
    autoplay_param: "autoplay", position: 2, active: true,
    templates: {
      "movie"   => "https://vidsrc.ir/embed/movie?imdb=%{imdb}&ds_lang=en",
      "series"  => "https://vidsrc.ir/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en",
      "episode" => "https://vidsrc.ir/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en",
      "anime"   => "https://vidsrc.ir/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en",
    },
  },
  {
    # Demoted 2026-09-04: named on the provider's own at-risk list. Still answering today
    # (301 -> vsembed.ru), so it stays active as a fallback rather than being switched
    # off, but nothing should prefer it.
    slug: "vidsrc-embed.ru", name: "vidsrc.ru", kind: "imdb",
    autoplay_param: "autoplay", position: 3, active: true,
    templates: {
      "movie"   => "https://vidsrc-embed.ru/embed/movie?imdb=%{imdb}&ds_lang=en",
      "series"  => "https://vidsrc-embed.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en",
      "episode" => "https://vidsrc-embed.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en",
      # vidsrc.ru has no anime-specific endpoint; anime plays through the tv one.
      "anime"   => "https://vidsrc-embed.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en",
    },
  },
  {
    # Demoted 2026-09-04: resolves to vidsrcme.ru, which is on the same at-risk list.
    slug: "vidsrcme", name: "VidSrc.me", kind: "imdb",
    autoplay_param: "autoplay", position: 4, active: true,
    templates: {
      "movie"   => "https://v2.vidsrc.me/embed/%{imdb}",
      "series"  => "https://v2.vidsrc.me/embed/%{series_imdb}/%{season}-%{episode}",
      "episode" => "https://v2.vidsrc.me/embed/%{series_imdb}/%{season}-%{episode}",
      "anime"   => "https://v2.vidsrc.me/embed/%{series_imdb}/%{season}-%{episode}",
    },
  },
  {
    # Kept deactivated: vidsrc.cc is currently offline. Retained so it can be
    # re-activated in the UI if it comes back (create-only seed won't undo that).
    slug: "vidsrc-cc", name: "VidSrc.cc", kind: "imdb",
    autoplay_param: "autoplay", position: 5, active: false,
    templates: {
      "movie"   => "https://vidsrc.cc/v3/embed/movie/%{imdb}",
      "series"  => "https://vidsrc.cc/v3/embed/tv/%{series_imdb}/%{season}/%{episode}",
      "episode" => "https://vidsrc.cc/v3/embed/tv/%{series_imdb}/%{season}/%{episode}",
      "anime"   => "https://vidsrc.cc/v2/embed/anime/%{series_imdb}/%{absolute_episode}/sub",
    },
  },
  {
    slug: "google-drive", name: "Google Drive", kind: "direct", position: 6, active: true,
    templates: { "default" => "https://drive.google.com/file/d/%{source_key}/preview" },
  },
  {
    slug: "mega", name: "MEGA", kind: "direct", position: 7, active: true,
    templates: { "default" => "https://mega.nz/embed/%{source_key}" },
  },
  {
    slug: "youtube", name: "YouTube", kind: "direct", position: 8, active: true,
    templates: { "default" => "https://www.youtube.com/embed/%{source_key}" },
  },
  {
    slug: "archive-org", name: "Internet Archive", kind: "direct", position: 9, active: true,
    templates: { "default" => "https://archive.org/embed/%{source_key}" },
  },
  {
    # Catch-all for heterogeneous one-off embeds (ok.ru, gotaku, anitaku, wikia, drive
    # folders, ...). source_key holds the full URL; template passes it through verbatim.
    slug: "custom", name: "Custom URL", kind: "direct", position: 99, active: true,
    templates: { "default" => "%{source_key}" },
  },
].freeze

SOURCES.each do |attrs|
  source = Source.find_or_initialize_by(slug: attrs[:slug])
  if source.new_record?
    source.assign_attributes(attrs)
    source.save!
    puts "✅ created #{source.slug} (#{source.kind}, active=#{source.active?})"
  else
    puts "↳ kept #{source.slug} (already exists, not modified)"
  end
end

puts "Sources in DB: #{Source.count}."
