# frozen_string_literal: true

# How each kind of notification reads on the page.
#
# Kept as a case per kind rather than as methods on the model: a notification is a row, and
# the wording, the tone and where "View" goes are all presentation. Adding a kind means
# adding a branch to each of these five.
module NotificationsHelper
  # :urgent / :warn / :info -- drives the stripe down the left of the card.
  def notification_tone(notification)
    case notification.kind
    when Notification::SOURCE_EXPIRING
      expired?(notification) ? :urgent : :warn
    when Notification::BROKEN_POSTER
      :warn
    else
      :info
    end
  end

  def notification_title(notification)
    case notification.kind
    when Notification::SOURCE_EXPIRING
      name = notification.data['name'].presence || 'A provider'
      expired?(notification) ? "#{name} has expired" : "#{name} is about to expire"
    when Notification::BROKEN_POSTER
      "#{notification.data['name'].presence || 'An entry'} has no poster"
    else
      notification.kind.humanize
    end
  end

  def notification_detail(notification)
    case notification.kind
    when Notification::SOURCE_EXPIRING then source_expiry_detail(notification)
    when Notification::BROKEN_POSTER then broken_poster_detail(notification)
    else ''
    end
  end

  # Where "View" goes, or nil for a notification with nowhere useful to send you.
  def notification_action_path(notification)
    case notification.kind
    when Notification::SOURCE_EXPIRING then sources_path
    # nil once the entry is gone. The next scan retires the row anyway; until then the
    # card still reads correctly from `data`, it just has nowhere to send you.
    when Notification::BROKEN_POSTER then notification.subject && entry_path(notification.subject)
    end
  end

  # Does following "View" also clear the notification?
  #
  # True for the kinds that are a to-do rather than a state to keep an eye on: you are
  # being sent somewhere to fix something, and the card has done its job once you are
  # there. An expiry warning is the other sort -- it should outlive being looked at.
  def notification_view_dismisses?(notification)
    notification.kind == Notification::BROKEN_POSTER
  end

  private

  def expiry_date(notification)
    Date.parse(notification.data['valid_until'].to_s)
  rescue Date::Error, TypeError
    nil
  end

  def expired?(notification)
    date = expiry_date(notification)
    date.present? && date < Date.current
  end

  def broken_poster_detail(notification)
    where = notification.data['list'].presence
    reason = notification.data['reason'].presence || 'did not load'
    held = notification.data['source'] == 'poster' ? 'Its uploaded poster' : 'The image it links to'

    "#{held} #{reason == 'no image on the entry' ? 'is missing' : "answered #{reason}"}" \
      "#{where ? " -- in #{where}" : ''}. Open it and pick a new one."
  end

  def source_expiry_detail(notification)
    date = expiry_date(notification)
    slug = notification.data['slug']
    return "#{slug} has no expiry date recorded." if date.nil?

    days = (date - Date.current).to_i

    if days.negative?
      "#{slug} lapsed on #{date.to_fs(:long)}, #{pluralize(days.abs, 'day')} ago. " \
        'Anything still playing through it is relying on it not having been reclaimed yet.'
    elsif days.zero?
      "#{slug} is due today. Renew it or switch channels to another provider."
    else
      "#{slug} is due on #{date.to_fs(:long)}, in #{pluralize(days, 'day')}."
    end
  end
end
