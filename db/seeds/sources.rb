# frozen_string_literal: true

# Kept as an entry point because `rails db:seed` and older notes point at it. The providers
# themselves, and the rules about what a sync may and may not touch, live in
# app/services/source_catalog.rb -- see there before changing anything.

result = SourceCatalog.sync!

result.created.each { |slug| puts "✅ created #{slug}" }
result.kept.each    { |slug| puts "↳ kept #{slug} (already present, not modified)" }
result.failed.each  { |slug| puts "⚠️  failed #{slug} -- see the log" }

puts "Sources in DB: #{Source.count}."
