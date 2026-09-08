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
  # private, or have embedding switched off by its uploader, and any of those shows up as a
  # dead frame in the middle of a break rather than as an error anybody sees. oEmbed answers
  # without an API key: 200 means the video is there and public.
  desc "Ask YouTube whether each reel is still playable"
  task check: :environment do
    CommercialReel.in_order.find_each do |reel|
      url = "https://www.youtube.com/oembed?format=json&url=" \
            "#{CGI.escape("https://www.youtube.com/watch?v=#{reel.youtube_id}")}"
      response = HTTParty.get(url, timeout: 10)
      ok = response.code == 200
      puts "#{ok ? '✅' : '⚠️ '} #{reel.label.ljust(10)} #{reel.youtube_id}  #{ok ? response.parsed_response['title'] : "HTTP #{response.code}"}"
    rescue StandardError => e
      puts "⚠️  #{reel.label.ljust(10)} #{reel.youtube_id}  #{e.class}"
    end
  end
end
