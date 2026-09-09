# frozen_string_literal: true

namespace :entries do
  # Fill in the per-episode runtimes SeasonImporter used to drop.
  #
  # TMDB returns a runtime with every episode of a season, in the same payload the importer
  # already reads to create them, and it was going unsaved. Everything laid out before this
  # therefore has episodes with no runtime at all, which leaves the cable schedule guessing
  # a flat thirty minutes for a series and cutting longer episodes off partway through.
  #
  # One request per season, and only for seasons that need one. Safe to run again: an
  # episode that already has a runtime is left alone.
  desc "Fetch per-episode runtimes from TMDB for episodes that have none"
  task backfill_episode_runtimes: :environment do
    scope = Entry.where(media: %w[series anime]).where.not(tmdb: [nil, ""])
    filled = 0
    seasons = 0
    skipped = []

    scope.find_each do |entry|
      entry.subentries.where(length: [nil, 0]).group_by(&:season).each do |season, episodes|
        next skipped << "#{entry.name} (no season number)" if season.blank?

        seasons += 1
        data = TmdbService.new.fetch_season(entry.tmdb, season)
        runtimes = (data["episodes"] || []).to_h { |e| [e["episode_number"], e["runtime"]] }

        episodes.each do |episode|
          minutes = runtimes[episode.episode]
          next if minutes.to_i <= 0

          episode.update_column(:length, minutes)
          filled += 1
        end
      rescue StandardError => e
        # One season that will not answer is a handful of episodes still guessed at, not a
        # reason to abandon the rest of the library.
        skipped << "#{entry.name} S#{season}: #{e.class}"
      end
    end

    puts "Episode runtimes: #{filled} filled across #{seasons} season(s) asked for."
    skipped.first(20).each { |line| puts "⚠️  #{line}" }
    puts "(#{skipped.size - 20} more skipped)" if skipped.size > 20
  end
end
