namespace :sources do
  desc "Report how many entries still depend on the legacy source columns"
  task audit: :environment do
    total = Entry.count
    legacy = []
    unplayable = []

    Entry.includes(:list, :provider, :subentries).find_each do |entry|
      # Series/anime templates need an episode. At playback time that comes from the
      # user's position, so fall back to the first episode rather than reporting an entry
      # as legacy-dependent just because `current` was never set.
      subentry = entry.current || entry.subentries.min_by { |s| [s.season.to_i, s.episode.to_i] }

      # What the provider templates can build on their own, ignoring the fallback.
      next if entry.resolved_source&.url_for(entry, subentry: subentry).presence

      if entry.embed_url(subentry: subentry).present?
        legacy << entry
      else
        unplayable << entry
      end
    end

    puts "Entries:                      #{total}"
    puts "Resolve via a Source:         #{total - legacy.size - unplayable.size}"
    puts "Fall back to legacy columns:  #{legacy.size}"
    puts "Resolve to nothing at all:    #{unplayable.size}"

    if legacy.any?
      puts "\nStill needing the legacy columns (first 20):"
      legacy.first(20).each { |e| puts "  ##{e.id} #{e.media.to_s.ljust(8)} imdb=#{e.imdb.inspect.ljust(14)} #{e.name.to_s.truncate(40)}" }
      puts "\nThe columns cannot be dropped while this is above zero."
    else
      puts "\nNothing depends on entries.source / source_two any more; they are safe to drop."
    end

    if unplayable.any?
      puts "\nNo playable URL from either path (first 20) -- these are already broken:"
      unplayable.first(20).each { |e| puts "  ##{e.id} #{e.media.to_s.ljust(8)} imdb=#{e.imdb.inspect.ljust(14)} #{e.name.to_s.truncate(40)}" }
    end
  end

  desc "Point lists/entries at an active provider when theirs was deactivated (dry run unless APPLY=1)"
  task repoint_inactive: :environment do
    apply = ENV["APPLY"] == "1"
    replacement = Source.active.where(kind: "imdb").order(:position).first
    abort "No active imdb source to repoint to." unless replacement

    inactive_ids = Source.where(active: false).pluck(:id)
    if inactive_ids.empty?
      puts "Every referenced source is active; nothing to do."
      next
    end

    lists = List.where(provider_id: inactive_ids)
    # Entries keep a direct provider even when deactivated: its source_key is specific to
    # that provider, so a swap would produce a URL for the wrong service.
    entries = Entry.where(provider_id: inactive_ids).where.not(imdb: [nil, ""]).where(source_key: [nil, ""])

    puts "Replacement: #{replacement.slug}"
    puts "Lists to repoint:   #{lists.count}"
    puts "Entries to repoint: #{entries.count}"

    if apply
      lists.update_all(provider_id: replacement.id)
      entries.update_all(provider_id: replacement.id)
      puts "Applied."
    else
      puts "Dry run. Re-run with APPLY=1 to persist."
    end
  end
end
