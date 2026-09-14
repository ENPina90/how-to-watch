# frozen_string_literal: true

# The weekly new-episode sweep: extends every `series` entry with what has aired since, and
# tells the owner of its channel about each episode added.
#
# An event, not a state, which is the opposite of the admin sweeps beside it. There is
# nothing to reconcile: an episode was added once, the notification says so once, and
# dismissing it is the end of it. The key carries the subentry, so a rerun that finds
# nothing new writes nothing -- and one that somehow reaches the same episode again cannot
# tell anyone twice.
#
# Only the channel's owner is told -- whoever built the channel and put the show on it.
# Subscribers are not: on a default channel that is every account, most of them being told
# about episodes of shows they never picked.
#
# One entry failing -- TMDB down for a moment, a season that 404s -- is logged and passed
# over. The next week picks it up, because nothing about it was written.
class NewEpisodeNotifier
  Result = Struct.new(:checked, :added, :held_back, :notified, :failed, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(tmdb: TmdbService.new, today: Date.current)
    @tmdb = tmdb
    @today = today
  end

  def call
    result = Result.new(checked: 0, added: 0, held_back: 0, notified: 0, failed: 0)

    Entry.where(media: 'series').includes(:list).find_each do |entry|
      result.checked += 1
      sweep(entry, result)
    rescue TmdbService::RequestError, ActiveRecord::ActiveRecordError => e
      result.failed += 1
      Rails.logger.warn("New episode sweep skipped entry #{entry.id} (#{entry.name}): #{e.class}: #{e.message}")
    end

    result
  end

  private

  def sweep(entry, result)
    outcome = NewEpisodeImporter.new(entry: entry, tmdb: @tmdb, today: @today).call do |subentry, episode|
      notify(entry, subentry, episode)
      result.notified += 1
    end

    result.added += outcome.added.size
    result.held_back += outcome.held_back
  end

  def notify(entry, subentry, episode)
    Notification.create!(
      user_id: entry.list.user_id,
      kind: Notification::NEW_EPISODE,
      subject: subentry,
      dedupe_key: "#{Notification::NEW_EPISODE}:#{subentry.id}",
      # Denormalised, as the other kinds are, so the card still reads correctly after the
      # entry is renamed or deleted.
      data: {
        'show' => entry.show_name,
        'entry' => entry.name,
        'list' => entry.list.name,
        'season' => subentry.season,
        'episode' => subentry.episode,
        'title' => subentry.name,
        'air_date' => episode['air_date']
      }
    )
  end
end
