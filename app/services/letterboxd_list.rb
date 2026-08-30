# frozen_string_literal: true

# Builds and refreshes the channel that mirrors a member's Letterboxd diary.
#
# One channel per user, found by the `letterboxd` flag rather than by name so that
# renaming it does not strand it. Syncing is idempotent: films are matched on their TMDB
# id, so re-running only adds what is new and refreshes scores that changed.
class LetterboxdList
  NAME_SUFFIX = "'s Letterbox"

  Result = Struct.new(:created, :updated, :total, keyword_init: true)

  def self.name_for(user)
    "#{user.display_name.capitalize}#{NAME_SUFFIX}"
  end

  def initialize(user)
    @user = user
  end

  attr_reader :user

  def list
    user.lists.find_by(letterboxd: true)
  end

  # Pulls the diary and reconciles it into the channel, creating the channel on first run.
  # Raises LetterboxdFeed::RequestError if the diary cannot be read -- callers decide
  # whether that is worth surfacing or just worth logging.
  def sync!
    return Result.new(created: 0, updated: 0, total: 0) unless user.letterboxd_enabled?

    watches = LetterboxdFeed.new(user.username).watches
    channel = find_or_create_list
    created = 0
    updated = 0

    # Oldest first, so positions in the channel read in the order they were watched.
    watches.reverse_each do |watch|
      entry = channel.entries.find_by(tmdb: watch.tmdb_id)

      if entry
        updated += 1 if refresh(entry, watch)
      else
        entry = create_entry(channel, watch)
        created += 1
      end

      mark_watched(entry, watch)
    end

    Result.new(created: created, updated: updated, total: watches.size)
  end

  # Disabling the feature takes the channel with it. List's own before_destroy clears the
  # entry graph in bulk, so this does not need to walk the entries itself.
  def remove!
    list&.destroy
  end

  private

  def find_or_create_list
    list || user.lists.create!(
      name: self.class.name_for(user),
      letterboxd: true,
      private: true,
      # Ratings come from Letterboxd, so the in-app review prompt would be asking for a
      # second opinion the diary already holds.
      reviewable: false
    )
  end

  def create_entry(channel, watch)
    channel.entries.create!(
      name: watch.title,
      year: watch.year,
      media: 'movie',
      tmdb: watch.tmdb_id,
      imdb: imdb_id_for(watch),
      pic: watch.poster_url,
      letterboxd_score: watch.rating,
      position: Entry.next_position(channel)
    )
  end

  # Returns true when something actually changed, so the caller can report a real count.
  def refresh(entry, watch)
    entry.letterboxd_score = watch.rating
    entry.imdb = imdb_id_for(watch) if entry.imdb.blank?

    return false unless entry.changed?

    entry.save!
    true
  end

  # The feed identifies films by TMDB id only, but playback resolves through IMDb for
  # most providers, so an entry without one is listed and not watchable. The lookup is
  # cached for 12h by TmdbService and only runs for films new to the channel.
  def imdb_id_for(watch)
    TmdbService.new.fetch_imdb_id(watch.tmdb_id, 'movie').presence
  rescue TmdbService::RequestError => e
    Rails.logger.warn("Letterboxd sync could not resolve an IMDb id for TMDB #{watch.tmdb_id}: #{e.message}")
    nil
  end

  # Columns are written directly because UserEntry#set_completed_at stamps Time.current
  # over completed_at whenever `completed` changes. That is right for someone ticking the
  # eye on a card and wrong here: the diary knows the date the film was actually watched,
  # and re-dating a five-year-old entry to today would be the only record of it.
  def mark_watched(entry, watch)
    user_entry = user.user_entry_for!(entry)
    # in_time_zone, not to_time: to_time reads midnight in the *server's* zone, which for
    # a server west of the app's UTC lands the watch on the previous day.
    watched_at = watch.watched_on&.in_time_zone || Time.current

    return if user_entry.completed? && user_entry.completed_at&.to_date == watched_at.to_date

    user_entry.update_columns(
      completed: true,
      completed_at: watched_at,
      last_watched_at: watched_at,
      updated_at: Time.current
    )
  end
end
