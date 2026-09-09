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
