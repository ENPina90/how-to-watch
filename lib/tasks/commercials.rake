# frozen_string_literal: true

namespace :commercials do
  desc "Create any commercial reel this app ships with that the database does not have yet"
  task seed: :environment do
    result = CommercialCatalog.sync!

    result.created.each { |label| puts "✅ created #{label}" }
    result.kept.each    { |label| puts "↳ kept #{label} (already present, not modified)" }
    result.failed.each  { |label| puts "⚠️  failed #{label} -- see the log" }

    puts "Commercial reels: #{result.summary}."
  end

  # Runs on every deploy from the Procfile, so it must not be able to stop the app booting.
  # A reel that cannot be created is a break that falls back to the caption, not a reason to
  # refuse to start; CommercialCatalog.sync! already swallows per-reel failures, and this
  # catches anything worse -- an unmigrated database on a half-finished deploy, say.
  desc "commercials:seed, but never fails the boot (used by the Procfile)"
  task seed_quietly: :environment do
    result = CommercialCatalog.sync!
    puts "Commercial reels: #{result.summary}." if result.created.any? || result.failed.any?
  rescue StandardError => e
    warn "commercials:seed_quietly skipped: #{e.class}: #{e.message}"
  end

  # How long each reel actually runs, read off the watch page.
  #
  # Without it a break can only start somewhere in the first few minutes, because there is
  # no telling how much reel there is to spend -- so every break on a channel opens with
  # roughly the same adverts. With it, a break can begin anywhere in an hour of them.
  #
  # `lengthSeconds` is not a documented API and could move, which is why a reel it cannot
  # read is left alone rather than blanked: a runtime already known is better than none.
  desc "Fill in how long each commercial reel runs"
  task durations: :environment do
    CommercialReel.in_order.find_each do |reel|
      # The same reading the Runtime button on /admin/commercial_reels does, so there is
      # one implementation of it and one set of answers.
      seconds = YoutubeVideoFacts.for(reel.youtube_id).duration_seconds

      if seconds&.positive?
        reel.update!(duration_seconds: seconds)
        puts "✅ #{reel.label.ljust(10)} #{(seconds / 60.0).round(1)} min"
      else
        puts "❔ #{reel.label.ljust(10)} could not read a runtime -- left as #{reel.duration_seconds.inspect}"
      end
    end
  end

  # Whether YouTube will still hand each reel over. A compilation can be taken down, made
  # private, or have embedding switched off by its uploader, and any of those is a dead frame
  # in the middle of a break rather than an error anybody sees.
  #
  # Two questions, because they are two different flags and only asking the first is how
  # this task once reported a clean sweep it could not actually vouch for:
  #
  #   oEmbed answers whether the video exists and is public. It says nothing at all about
  #   embedding, and returns 200 for a video no embed will ever play.
  #
  #   `playableInEmbed`, read off the watch page, is the one that matters. It is not a
  #   documented API and could move, which is why a missing flag reports as unknown rather
  #   than as a pass.
  #
  # Neither can see a refusal that only happens in a browser. The page handles that itself:
  # a reel that will not start is replaced by the caption rather than left on screen.
  desc "Ask YouTube whether each reel is still there, and still embeddable"
  task check: :environment do
    agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
            "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"

    CommercialReel.in_order.find_each do |reel|
      watch = "https://www.youtube.com/watch?v=#{reel.youtube_id}"
      oembed = HTTParty.get("https://www.youtube.com/oembed?format=json&url=#{CGI.escape(watch)}",
                            timeout: 15)

      unless oembed.code == 200
        puts "⚠️  #{reel.label.ljust(10)} #{reel.youtube_id}  gone or private (HTTP #{oembed.code})"
        next
      end

      body = HTTParty.get(watch, headers: { "User-Agent" => agent }, timeout: 20).body.to_s
      embeddable = body[/"playableInEmbed":(true|false)/, 1]
      title = oembed.parsed_response["title"].to_s.truncate(58)

      case embeddable
      when "true"  then puts "✅ #{reel.label.ljust(10)} #{reel.youtube_id}  #{title}"
      when "false" then puts "⚠️  #{reel.label.ljust(10)} #{reel.youtube_id}  EMBEDDING DISABLED -- #{title}"
      else              puts "❔ #{reel.label.ljust(10)} #{reel.youtube_id}  cannot tell -- #{title}"
      end
    rescue StandardError => e
      puts "⚠️  #{reel.label.ljust(10)} #{reel.youtube_id}  #{e.class}: #{e.message.truncate(60)}"
    end
  end
end
