# frozen_string_literal: true

namespace :sources do
  desc "Create any provider this app ships with that the database does not have yet"
  task seed: :environment do
    result = SourceCatalog.sync!

    result.created.each { |slug| puts "✅ created #{slug}" }
    result.kept.each    { |slug| puts "↳ kept #{slug} (already present, not modified)" }
    result.failed.each  { |slug| puts "⚠️  failed #{slug} -- see the log" }

    puts "Sources: #{result.summary}."
  end

  # Runs on every deploy from the Procfile, so it must not be able to stop the app booting.
  # A provider that cannot be created is a page an admin has to fix, not a reason to refuse
  # to start; SourceCatalog.sync! already swallows per-provider failures, and this catches
  # anything worse -- an unmigrated database on a half-finished deploy, say.
  desc "sources:seed, but never fails the boot (used by the Procfile)"
  task seed_quietly: :environment do
    result = SourceCatalog.sync!
    puts "Sources: #{result.summary}." if result.created.any? || result.failed.any?
  rescue StandardError => e
    warn "sources:seed_quietly skipped: #{e.class}: #{e.message}"
  end

  desc "Show where the database disagrees with the providers this app ships with"
  task status: :environment do
    missing = SourceCatalog.missing
    drift = SourceCatalog.drift

    if missing.any?
      puts "Not in the database yet (run sources:seed):"
      missing.each { |slug| puts "  + #{slug}" }
      puts
    end

    if drift.any?
      puts "Edited in the database, and left that way on purpose unless you say otherwise:"
      drift.each do |entry|
        puts "  ~ #{entry[:slug]}"
        entry[:differences].each do |field, values|
          puts "      #{field}"
          puts "        shipped: #{values[:declared].inspect}"
          puts "        in db:   #{values[:actual].inspect}"
        end
      end
      puts
      puts "A sync never overwrites these. Change one in the admin UI at /sources if the"
      puts "database is the one that is wrong."
    end

    puts "In step with the shipped list." if missing.empty? && drift.empty?
  end
end
