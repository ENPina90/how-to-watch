namespace :sources do
  desc "Propose provider wiring for entries that still need the legacy source columns " \
       "(dry run unless APPLY=1; title guesses need APPLY_GUESSES=1 as well)"
  task resolve_missing: :environment do
    apply = ENV["APPLY"] == "1"
    apply_guesses = ENV["APPLY_GUESSES"] == "1"

    entries = Entry.includes(:list, :provider, :subentries).select do |entry|
      subentry = entry.current || entry.subentries.min_by { |s| [s.season.to_i, s.episode.to_i] }
      entry.resolved_source&.url_for(entry, subentry: subentry).blank?
    end

    puts "#{entries.size} entries cannot resolve through a Source template.\n\n"

    grouped = Hash.new { |h, k| h[k] = [] }
    entries.each do |entry|
      proposal = MissingSourceResolver.new(entry).call
      grouped[proposal[:strategy]] << proposal
    end

    %i[imdb_in_url imdb_from_tmdb direct_source title_search none].each do |strategy|
      proposals = grouped[strategy]
      next if proposals.empty?

      puts "── #{strategy} (#{proposals.size}) ".ljust(100, '─')
      proposals.each do |p|
        entry = p[:entry]
        fix = if p[:provider] then "provider=#{p[:provider].slug} key=#{p[:source_key].to_s[0, 28]}"
              elsif p[:imdb] then "imdb=#{p[:imdb]}"
              else '(nothing to apply)'
              end
        puts "  ##{entry.id.to_s.rjust(5)} #{entry.name.to_s[0, 34].ljust(34)} #{fix.ljust(46)} #{p[:note]}"
        p[:candidates].drop(1).each { |c| puts "        also: #{c[:imdb]} #{c[:title]} (#{c[:year]}) via #{c[:via]}" }
      end
      puts
    end

    applied = 0
    skipped_guesses = 0

    grouped.values.flatten.each do |p|
      next if p[:strategy] == :none
      # A title match is a guess. For fan edits it is usually the *official* film, which
      # would quietly replace someone's cut with the studio release -- so it needs its own
      # opt-in flag.
      if p[:strategy] == :title_search && !apply_guesses
        skipped_guesses += 1
        next
      end

      attrs = {}
      attrs[:imdb] = p[:imdb] if p[:imdb].present?
      attrs[:provider] = p[:provider] if p[:provider]
      attrs[:source_key] = p[:source_key] if p[:source_key].present?
      next if attrs.empty?

      p[:entry].update_columns(attrs) if apply
      applied += 1
    end

    puts "Would apply: #{applied} entries" unless apply
    puts "Applied: #{applied} entries" if apply
    puts "Title guesses held back: #{skipped_guesses} (re-run with APPLY_GUESSES=1 to include them)" if skipped_guesses.positive?
    puts "Dry run. Re-run with APPLY=1 to persist." unless apply
  end
end
