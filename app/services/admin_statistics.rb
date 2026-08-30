# frozen_string_literal: true

# The numbers on the admin dashboard, gathered in one place so the view holds no queries.
#
# Everything is either a count or a grouped count, and the window is the same seven days
# throughout, so the figures on the page can be read against each other.
class AdminStatistics
  WINDOW = 7

  def initialize(window: WINDOW)
    @window = window
    @since = Date.current - (window - 1)
  end

  attr_reader :window, :since

  # People. `active` is the accounts that actually opened a page this week, which is the
  # only sense in which this app knows a user is around -- Devise's trackable module is not
  # enabled, so there is no last_sign_in_at to read.
  def users_total = User.count
  def users_new = User.where(created_at: since.beginning_of_day..).count
  def users_active = Visit.since(since).where.not(user_id: nil).distinct.count(:user_id)
  def admins = User.where(admin: true).count

  # Traffic. A visit is one browser on one day; page views are the requests behind them.
  def visits = Visit.since(since).count
  def page_views = Visit.since(since).sum(:page_views)
  def guest_visits = Visit.since(since).where(user_id: nil).count

  # Each of the last N days as [date, visits, page_views], oldest first, including the days
  # nobody came -- a gap in a chart should read as zero, not as a missing bar.
  def daily_visits
    counted = Visit.since(since).group(:visited_on).pluck(:visited_on, Arel.sql('COUNT(*)'), Arel.sql('SUM(page_views)'))
    by_day = counted.to_h { |day, visits, views| [day, [visits, views.to_i]] }

    (since..Date.current).map do |day|
      visits, views = by_day.fetch(day, [0, 0])
      { date: day, visits: visits, page_views: views }
    end
  end

  # Content.
  def lists_total = List.count
  def lists_new = List.where(created_at: since.beginning_of_day..).count
  def entries_total = Entry.count
  def entries_new = Entry.where(created_at: since.beginning_of_day..).count
  def private_lists = List.where(private: true).count
  def subscriptions = Subscription.count

  # Watching. completed_at is set when an entry is marked watched, so this is activity
  # rather than inventory.
  def completions = UserEntry.where(completed: true, completed_at: since.beginning_of_day..).count
  def completions_total = UserEntry.where(completed: true).count

  # Providers, which is the one piece of configuration a broken deploy shows up in first.
  def sources_active = Source.where(active: true).count
  def sources_total = Source.count

  # The channels people are actually filling, biggest first.
  def busiest_lists(limit = 5)
    List.left_joins(:entries)
        .group('lists.id')
        .order(Arel.sql('COUNT(entries.id) DESC'))
        .limit(limit)
        .pluck(Arel.sql('lists.id, lists.name, COUNT(entries.id)'))
        .map { |id, name, count| { id: id, name: name, entries: count } }
  end

  # The most-watched entries across everyone, which is the closest thing the site has to a
  # chart of what it is for.
  def most_watched(limit = 5)
    Entry.joins(:user_entries)
         .where(user_entries: { completed: true })
         .group('entries.id')
         .order(Arel.sql('COUNT(user_entries.id) DESC'))
         .limit(limit)
         .pluck(Arel.sql('entries.id, entries.name, COUNT(user_entries.id)'))
         .map { |id, name, count| { id: id, name: name, watches: count } }
  end
end
