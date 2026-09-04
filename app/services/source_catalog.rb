# frozen_string_literal: true

# The streaming providers this app ships with, and how they reach a database.
#
# The list is code so that adding a provider is a reviewable diff that travels with the
# deploy, rather than something typed into a form on each environment in turn and
# remembered differently in each.
#
# **Additive by design.** Existing rows are never modified: templates get edited through
# the admin UI when a provider changes its URL shape, providers get deactivated, and the
# order is dragged into place -- none of which should be undone by a deploy. So `sync!`
# only ever creates providers this app knows about and the database does not, which makes
# it safe to run unattended on every boot.
#
# What that costs is that a template change to an *existing* provider does not propagate.
# `drift` is the answer to that: it reports where the database and this list disagree, so
# the difference is visible rather than silently assumed away.
class SourceCatalog
  # Placeholders: %{imdb} %{series_imdb} %{season} %{episode} %{absolute_episode} %{source_key}
  # For series/anime the resolver is passed the current subentry; standalone episode
  # entries resolve season/episode from the entry itself.
  #
  # `valid_until` is when the provider's address should next be checked -- ours because the
  # registration lapses, vidsrc's because they rotate. Null for providers that cannot
  # lapse. Given in days, and resolved against the day it is seeded, because a fresh
  # database is being set up today whenever today is.
  #
  # Order here is the order a *fresh* database gets. Anything created into a database that
  # already has providers is appended instead, so a deploy can never reshuffle an order an
  # admin dragged into place -- and never lands a new provider at the top, where it would
  # silently become what channels fall back to.
  PROVIDERS = [
    {
      # Our own domain, CNAMEd to vidsrc (see docs/guides/VIDSRC.md §5). The only front door
      # that starts playing on its own: vidsrc bakes autoStart:true into the shell for a
      # custom domain and false for everyone else, so this is the one source where
      # autoplay=1 means what it says. Also half the ads and no vidsrc branding.
      #
      # autonext is left off: the app drives episode order itself, and vidsrc's own
      # advance is known to lose track of which episode it is on.
      slug: 'framerelay', name: 'Player', kind: 'imdb',
      autoplay_param: 'autoplay', active: true, valid_for_days: 365,
      templates: {
        'movie'   => 'https://framerelay.dev/embed/movie?imdb=%{imdb}&ds_lang=en',
        'series'  => 'https://framerelay.dev/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en',
        'episode' => 'https://framerelay.dev/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en',
        'anime'   => 'https://framerelay.dev/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en'
      }
    },
    {
      # vidsrc2.ru and vidsrc.ir are the two domains the provider told everyone to move to
      # on 2026-08-30, when it said its registrar had stopped answering for the older ones.
      # Both are default domains, so neither can skip the play button.
      slug: 'vidsrc2', name: 'VidSrc 2', kind: 'imdb',
      autoplay_param: 'autoplay', active: true, valid_for_days: 180,
      templates: {
        'movie'   => 'https://vidsrc2.ru/embed/movie?imdb=%{imdb}&ds_lang=en',
        'series'  => 'https://vidsrc2.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en',
        'episode' => 'https://vidsrc2.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en',
        # vidsrc has no anime-specific endpoint; anime plays through the tv one.
        'anime'   => 'https://vidsrc2.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en'
      }
    },
    {
      # Same backend as vidsrc2.ru, different front door -- kept as the immediate fallback
      # for when one of the two domains goes down.
      slug: 'vidsrc-ir', name: 'VidSrc IR', kind: 'imdb',
      autoplay_param: 'autoplay', active: true, valid_for_days: 180,
      templates: {
        'movie'   => 'https://vidsrc.ir/embed/movie?imdb=%{imdb}&ds_lang=en',
        'series'  => 'https://vidsrc.ir/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en',
        'episode' => 'https://vidsrc.ir/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en',
        'anime'   => 'https://vidsrc.ir/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en'
      }
    },
    {
      # Demoted 2026-09-04: named on the provider's own at-risk list. Still answering, so it
      # stays active as a fallback rather than being switched off.
      slug: 'vidsrc-embed.ru', name: 'vidsrc.ru', kind: 'imdb',
      autoplay_param: 'autoplay', active: true, valid_for_days: 60,
      templates: {
        'movie'   => 'https://vidsrc-embed.ru/embed/movie?imdb=%{imdb}&ds_lang=en',
        'series'  => 'https://vidsrc-embed.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en',
        'episode' => 'https://vidsrc-embed.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en',
        'anime'   => 'https://vidsrc-embed.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en'
      }
    },
    {
      # Demoted 2026-09-04: resolves to vidsrcme.ru, which is on the same at-risk list.
      slug: 'vidsrcme', name: 'VidSrc.me', kind: 'imdb',
      autoplay_param: 'autoplay', active: true, valid_for_days: 60,
      templates: {
        'movie'   => 'https://v2.vidsrc.me/embed/%{imdb}',
        'series'  => 'https://v2.vidsrc.me/embed/%{series_imdb}/%{season}-%{episode}',
        'episode' => 'https://v2.vidsrc.me/embed/%{series_imdb}/%{season}-%{episode}',
        'anime'   => 'https://v2.vidsrc.me/embed/%{series_imdb}/%{season}-%{episode}'
      }
    },
    {
      # Kept deactivated: vidsrc.cc is currently offline. Retained so it can be
      # re-activated in the UI if it comes back.
      slug: 'vidsrc-cc', name: 'VidSrc.cc', kind: 'imdb',
      autoplay_param: 'autoplay', active: false,
      templates: {
        'movie'   => 'https://vidsrc.cc/v3/embed/movie/%{imdb}',
        'series'  => 'https://vidsrc.cc/v3/embed/tv/%{series_imdb}/%{season}/%{episode}',
        'episode' => 'https://vidsrc.cc/v3/embed/tv/%{series_imdb}/%{season}/%{episode}',
        'anime'   => 'https://vidsrc.cc/v2/embed/anime/%{series_imdb}/%{absolute_episode}/sub'
      }
    },
    {
      slug: 'google-drive', name: 'Google Drive', kind: 'direct', active: true,
      templates: { 'default' => 'https://drive.google.com/file/d/%{source_key}/preview' }
    },
    {
      slug: 'mega', name: 'MEGA', kind: 'direct', active: true,
      templates: { 'default' => 'https://mega.nz/embed/%{source_key}' }
    },
    {
      slug: 'youtube', name: 'YouTube', kind: 'direct', active: true,
      templates: { 'default' => 'https://www.youtube.com/embed/%{source_key}' }
    },
    {
      slug: 'archive-org', name: 'Internet Archive', kind: 'direct', active: true,
      templates: { 'default' => 'https://archive.org/embed/%{source_key}' }
    },
    {
      # Catch-all for heterogeneous one-off embeds (ok.ru, gotaku, anitaku, wikia, drive
      # folders, ...). source_key holds the full URL; template passes it through verbatim.
      slug: 'custom', name: 'Custom URL', kind: 'direct', active: true,
      templates: { 'default' => '%{source_key}' }
    }
  ].freeze

  Result = Struct.new(:created, :kept, :failed, keyword_init: true) do
    def summary = "#{created.size} created, #{kept.size} already present, #{failed.size} failed"
  end

  # Creates whatever this app knows about and the database does not. Returns what it did
  # rather than raising, because this runs during boot: a provider that cannot be created
  # is worth reporting and is not worth refusing to start the app over.
  def self.sync!
    created = []
    kept = []
    failed = []

    PROVIDERS.each do |declared|
      if Source.exists?(slug: declared[:slug])
        kept << declared[:slug]
        next
      end

      begin
        create!(declared)
        created << declared[:slug]
      rescue ActiveRecord::RecordNotUnique
        # Two web instances booting at once. The other one won; that is a success.
        kept << declared[:slug]
      rescue StandardError => e
        Rails.logger.error("SourceCatalog could not create #{declared[:slug]}: #{e.class}: #{e.message}")
        failed << declared[:slug]
      end
    end

    Result.new(created: created, kept: kept, failed: failed)
  end

  # Where the database and this list disagree, for providers that exist in both. Reports
  # rather than repairs: an admin editing a template through the UI is the intended way to
  # respond to a provider changing its URLs, and this is how that becomes visible instead
  # of being mistaken for the list being wrong.
  def self.drift
    by_slug = Source.where(slug: PROVIDERS.map { |p| p[:slug] }).index_by(&:slug)

    PROVIDERS.filter_map do |declared|
      source = by_slug[declared[:slug]]
      next if source.nil?

      differences = compare(declared, source)
      { slug: declared[:slug], differences: differences } if differences.any?
    end
  end

  # Providers this app knows about that the database has never heard of.
  def self.missing
    PROVIDERS.map { |p| p[:slug] } - Source.where(slug: PROVIDERS.map { |p| p[:slug] }).pluck(:slug)
  end

  def self.create!(declared)
    Source.create!(
      slug: declared[:slug],
      name: declared[:name],
      kind: declared[:kind],
      autoplay_param: declared[:autoplay_param],
      active: declared[:active],
      templates: declared[:templates],
      valid_until: declared[:valid_for_days] && Date.current + declared[:valid_for_days],
      # Appended rather than given a number from the list: on a fresh database that is the
      # declared order anyway, and on a populated one it keeps a deploy from reshuffling an
      # order somebody set, or from dropping a new provider at the top where it would
      # quietly become the fallback.
      position: (Source.maximum(:position) || 0) + 1
    )
  end
  private_class_method :create!

  def self.compare(declared, source)
    differences = {}

    %i[name kind autoplay_param].each do |field|
      actual = source.public_send(field)
      differences[field] = { declared: declared[field], actual: actual } if declared[field].to_s != actual.to_s
    end

    differences[:active] = { declared: declared[:active], actual: source.active? } if declared[:active] != source.active?
    differences[:templates] = { declared: declared[:templates], actual: source.templates } if declared[:templates] != source.templates

    differences
  end
  private_class_method :compare
end
