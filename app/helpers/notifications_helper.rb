# frozen_string_literal: true

# How each kind of notification reads on the page.
#
# Kept as a case per kind rather than as methods on the model: a notification is a row, and
# the wording, the tone and where "View" goes are all presentation. Adding a kind means
# adding a branch to each of these four.
module NotificationsHelper
  # :urgent / :warn / :info -- drives the stripe down the left of the card.
  def notification_tone(notification)
    case notification.kind
    when Notification::SOURCE_EXPIRING
      expired?(notification) ? :urgent : :warn
    else
      :info
    end
  end

  def notification_title(notification)
    case notification.kind
    when Notification::SOURCE_EXPIRING
      name = notification.data['name'].presence || 'A provider'
      expired?(notification) ? "#{name} has expired" : "#{name} is about to expire"
    else
      notification.kind.humanize
    end
  end

  def notification_detail(notification)
    case notification.kind
    when Notification::SOURCE_EXPIRING then source_expiry_detail(notification)
    else ''
    end
  end

  # Where "View" goes, or nil for a notification with nowhere useful to send you.
  def notification_action_path(notification)
    case notification.kind
    when Notification::SOURCE_EXPIRING then sources_path
    end
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
