class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Auto-subscription callback
  after_create :setup_initial_subscriptions
  after_create :create_default_list
  # after_commit, not after_save: the job reads the user back from the database and
  # would find nothing if the transaction had not landed yet.
  after_commit :sync_letterboxd_channel, on: :create, if: :letterboxd_ready?
  after_commit :apply_letterboxd_change, on: :update, if: :letterboxd_settings_changed?

  # Channels belong to the account; the foreign key means a destroy raises without this.
  has_many :lists, dependent: :destroy
  has_many :user_entries, dependent: :destroy
  has_many :user_entry_positions, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :subscribed_lists, through: :subscriptions, source: :list
  has_many :watched_entries, -> { where(user_entries: { completed: true }) }, through: :user_entries, source: :entry
  has_many :unwatched_entries, -> { where(user_entries: { completed: false }) }, through: :user_entries, source: :entry
  has_many :reviewed_entries, -> { where.not(user_entries: { review: nil }) }, through: :user_entries, source: :entry
  has_many :user_list_positions, dependent: :destroy

  # The username is the Letterboxd handle, so there is nothing to link without one.
  validates :username, presence: { message: 'is needed to link a Letterboxd account' },
                       if: :letterboxd_enabled?

  # What to call this user in the UI. Both navbars used to build this inline, with
  # slightly different rules -- a blank-but-present username rendered as nothing in one
  # of them.
  def display_name
    username.presence || email.split('@').first.capitalize
  end

  # READ. nil when this user has never tracked the entry -- see Entry#user_entry_for for
  # why the read path must not create rows.
  def user_entry_for(entry)
    user_entries.find_by(entry: entry)
  end

  # WRITE. Creates the tracking row if it does not exist yet.
  def user_entry_for!(entry)
    user_entries.find_or_create_by(entry: entry)
  end

  # Check if user has completed an entry
  def completed?(entry)
    user_entry_for(entry)&.completed? || false
  end

  # Mark entry as completed for this user
  def mark_completed!(entry)
    user_entry_for!(entry).mark_completed!
  end

  # Mark entry as incomplete for this user
  def mark_incomplete!(entry)
    user_entry_for(entry)&.mark_incomplete!
  end

  # Toggle completion status for an entry
  def toggle_completed!(entry)
    user_entry_for!(entry).toggle_completed!
  end

  # Add review for an entry
  def review_entry!(entry, rating)
    user_entry_for!(entry).set_review!(rating)
  end

  # Add comment for an entry
  def comment_on_entry!(entry, comment)
    user_entry_for!(entry).set_comment!(comment)
  end

  # Get user's review for an entry
  def review_for(entry)
    user_entry_for(entry)&.review
  end

  # Get user's comment for an entry
  def comment_for(entry)
    user_entry_for(entry)&.comment
  end

  # Remove user's tracking for an entry (delete UserEntry record)
  def remove_tracking_for!(entry)
    user_entries.where(entry: entry).destroy_all
  end

  # Check if user can edit a list
  def can_edit_list?(list)
    admin? || list.user == self || list.default?
  end

  # Check if user can edit an entry
  def can_edit_entry?(entry)
    admin? || entry.list.user == self || entry.list.default?
  end

  # Check if user can set default lists
  def can_set_default?
    admin?
  end

  # Subscription methods
  def subscribed_to?(list)
    subscriptions.exists?(list: list)
  end

  def subscribe_to!(list)
    return false if subscribed_to?(list)

    subscriptions.create!(list: list, subscribed_at: Time.current)
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def unsubscribe_from!(list)
    subscriptions.where(list: list).destroy_all
  end

  def toggle_subscription!(list)
    if subscribed_to?(list)
      unsubscribe_from!(list)
      false
    else
      subscribe_to!(list)
      true
    end
  end

  # --- Letterboxd -------------------------------------------------------------------
  # Linking is a username and an opt-in: the diary is read from the public RSS feed at
  # /<username>/rss/, which needs no credentials. See LetterboxdFeed.

  # Enough to attempt a sync. The username doubles as the Letterboxd handle, so opting in
  # without one leaves nothing to fetch.
  def letterboxd_ready?
    letterboxd_enabled? && LetterboxdFeed.valid_username?(username)
  end

  def letterboxd_list
    LetterboxdList.new(self).list
  end

  # What the profile page reports. :waiting covers both "queued" and "the worker never
  # picked it up", which look identical from here -- and a wait that never resolves is
  # itself the signal that nothing is running the queue.
  def letterboxd_sync_state
    return :off unless letterboxd_enabled?
    return :failed if letterboxd_sync_error.present?
    return :waiting if letterboxd_synced_at.blank?

    :ok
  end

  private

  def letterboxd_settings_changed?
    saved_change_to_letterboxd_enabled? || (letterboxd_enabled? && saved_change_to_username?)
  end

  # Turning it off deletes the channel outright, which is quick enough to do in the
  # request. Turning it on -- or pointing it at a different Letterboxd handle -- means
  # reading a feed and resolving ids, so that goes to a job.
  def apply_letterboxd_change
    if letterboxd_enabled?
      letterboxd_list&.update(name: LetterboxdList.name_for(self)) if saved_change_to_username?
      sync_letterboxd_channel
    else
      LetterboxdList.new(self).remove!
    end
  end

  def sync_letterboxd_channel
    LetterboxdSyncJob.perform_later(id)
  end

  def setup_initial_subscriptions
    Subscription.auto_subscribe_user(self)
  end

  def create_default_list
    list_name = generate_default_list_name
    lists.create!(
      name: list_name,
      private: true,
      mobile: true
    )
  end

  def generate_default_list_name
    if username.present?
      "#{username.capitalize}'s Favorites"
    else
      # Extract the part before @ from email and capitalize it
      email_prefix = email.split('@').first
      "#{email_prefix.capitalize}'s Favorites"
    end
  end
end
