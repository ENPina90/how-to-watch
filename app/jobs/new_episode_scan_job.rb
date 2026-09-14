# frozen_string_literal: true

# Looks for episodes aired since each series was filled in, adds them, and tells the
# channel's owner. See NewEpisodeImporter for how a released episode is told apart from
# a placeholder, which is the part that needs care.
#
# Weekly, on a Thursday. Most shows go out between Sunday and Wednesday, and the importer
# will not take an episode on its air date, so a Thursday run catches the week's broadcasts
# with a day in hand. One a day would find the same episodes a few days sooner and spend
# seven times the TMDB requests doing it.
class NewEpisodeScanJob < ApplicationJob
  queue_as :default

  def perform
    result = NewEpisodeNotifier.call

    Rails.logger.info(
      "New episode scan: #{result.checked} series checked, #{result.added} episode(s) added, " \
      "#{result.held_back} held back as incomplete, #{result.notified} notification(s) sent, " \
      "#{result.failed} failed"
    )
  end
end
