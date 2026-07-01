namespace :sources do
  # Reversible backfill of the new provider FK + source_key from legacy columns.
  # DRY RUN by default (no writes). Run `rails sources:backfill APPLY=1` to persist.
  # Legacy columns (source, source_two, preferred_source) are never modified.
  desc "Backfill provider_id / source_key from legacy source columns (dry run unless APPLY=1)"
  task backfill: :environment do
    apply = ENV["APPLY"] == "1"

    sources = Source.all.index_by(&:slug)
    vc = sources.fetch("vidsrc-cc")
    vm = sources.fetch("vidsrcme")

    # int preferred_source (1/2) -> imdb provider
    imdb_for = ->(pref) { pref == 2 ? vm : vc }

    # Classify a legacy source URL -> [provider_slug, source_key | nil]. nil provider => imdb-keyed.
    classify = lambda do |url|
      return [nil, nil] if url.blank?
      case url
      when %r{vidsrc}i
        [nil, nil] # imdb-keyed (vidsrc.cc / v2.vidsrc.me / vidsrc.net / vidsrc.xyz)
      when %r{drive\.google\.com/(?:file/d/|embed/d/)([^/?]+)}i
        ["google-drive", Regexp.last_match(1)]
      when %r{drive\.google\.com/drive/folders}i
        ["custom", url] # folders aren't single-file embeds -> pass through verbatim
      when %r{mega\.nz/embed/(.+)\z}i
        ["mega", Regexp.last_match(1)]
      when %r{youtube\.com/embed/(.+)\z}i
        ["youtube", Regexp.last_match(1)]
      when %r{archive\.org/embed/(.+)\z}i
        ["archive-org", Regexp.last_match(1)]
      else
        ["custom", url] # ok.ru, gotaku, anitaku, wikia, protocol-relative, ...
      end
    end

    list_stats  = Hash.new(0)
    entry_stats = Hash.new(0)
    samples     = Hash.new { |h, k| h[k] = [] }

    ActiveRecord::Base.transaction do
      # ---- Lists: provider from int preferred_source (defaults to 1) ----
      List.find_each do |list|
        provider = imdb_for.call(list.preferred_source)
        list_stats[provider.slug] += 1
        list.update_column(:provider_id, provider.id) if apply
      end

      # ---- Entries ----
      Entry.find_each do |entry|
        slug, key = classify.call(entry.source)

        if slug.nil?
          # imdb-keyed: only pin a provider when the entry overrides the list default.
          if entry.preferred_source.present?
            provider = imdb_for.call(entry.preferred_source)
            entry_stats["imdb-override:#{provider.slug}"] += 1
            entry.update_columns(provider_id: provider.id, source_key: nil) if apply
          else
            entry_stats["imdb-inherit"] += 1 # leave provider_id null -> inherits list.provider
          end
        else
          provider = sources.fetch(slug)
          entry_stats["direct:#{slug}"] += 1
          samples[slug] << "##{entry.id} #{entry.source}  ->  key=#{key}" if samples[slug].size < 4
          entry.update_columns(provider_id: provider.id, source_key: key) if apply
        end
      end

      raise ActiveRecord::Rollback unless apply
    end

    puts "\n=== #{apply ? 'APPLIED' : 'DRY RUN (no writes)'} ==="
    puts "\nLists -> provider:"
    list_stats.sort.each { |k, v| puts "  #{v}\t#{k}" }
    puts "\nEntries:"
    entry_stats.sort.each { |k, v| puts "  #{v}\t#{k}" }
    puts "\nDirect-source key extraction samples:"
    samples.sort.each do |slug, rows|
      puts "  [#{slug}]"
      rows.each { |r| puts "    #{r}" }
    end
    puts "\n#{apply ? 'Persisted.' : 'No changes written. Re-run with APPLY=1 to persist.'}"
  end

  # Reverse the backfill: clear the new provider_id / source_key columns so entries fall
  # back to the legacy source columns (which are never modified). Safe and idempotent.
  desc "Undo the source backfill (clear provider_id/source_key; legacy columns untouched)"
  task backfill_undo: :environment do
    entries = Entry.where.not(provider_id: nil).or(Entry.where.not(source_key: nil)).count
    lists   = List.where.not(provider_id: nil).count

    Entry.update_all(provider_id: nil, source_key: nil)
    List.update_all(provider_id: nil)

    puts "Cleared provider_id/source_key on #{entries} entries and provider_id on #{lists} lists."
    puts "Legacy source / source_two / preferred_source columns were NOT modified."
  end
end
