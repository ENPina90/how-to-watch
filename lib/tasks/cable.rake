# frozen_string_literal: true

namespace :cable do
  # The guide reaches three days behind the present, but only the job's own output is there
  # to find -- and the job lays out one day at a time, so a dial that has just started
  # running has nothing to the left of this morning. This fills that in.
  #
  # What it writes is a day as it *would* have been, not a record of one: it draws from
  # today's catalogue, so an entry added this week can turn up in a listing for last
  # Tuesday. That is fine for the thing this is for -- giving the guide a past to scroll
  # through -- and is why it is a task somebody runs rather than something the guide does
  # for itself when it finds a day missing.
  #
  # `ensure_day!` throughout, so a day that really did air is never overwritten.
  desc "Lay out the last N days of listings, so the guide has a past to scroll back to"
  task :backfill, [:days] => :environment do |_task, args|
    days = (args[:days].presence || CableSchedule::GUIDE_LEAD_HOURS / 24).to_i
    abort "cable:backfill wants a positive number of days" unless days.positive?

    channels = CableSchedule.channels.to_a
    abort "There are no cable channels to lay out." if channels.empty?

    dates = (1..days).map { |back| CableSchedule.today - back }.reverse

    dates.each do |date|
      channels.each do |channel|
        written = CableSchedule.ensure_day!(channel, date)

        puts(if written.zero?
               "↳ #{date} #{channel.name}: left alone (already laid out, or nothing it can play)"
             else
               "✅ #{date} #{channel.name}: #{written} programmes"
             end)
      end
    end

    puts "Backfilled #{dates.first}..#{dates.last} for #{channels.length} channels."
  end
end
