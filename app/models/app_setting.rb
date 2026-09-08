# frozen_string_literal: true

# The site's own switches, as one row. Read it through `AppSetting.current`, which memoises
# for the length of the request: every request asks who is allowed in, and that question
# should not cost a query per call.
class AppSetting < ApplicationRecord
  # How much of the site a visitor without an account can reach.
  #
  #   secure   -- nothing. Sign in first, which is how the site has always worked.
  #   moderate -- browse: the channel index, a channel's page, search. Watching needs an
  #               account, because watching is the thing worth having one for.
  #   open     -- browse and watch. Everything that writes still needs an account: there is
  #               nowhere to record a position, a review or a new channel without one.
  ACCESS_MODES = %w[secure moderate open].freeze

  # How far through a film the up-next countdown appears, as a fraction of the runtime.
  #
  # It cannot sensibly come before the completion mark. Both routes to the card are gated
  # on the film counting as watched -- windowed, crossing this raises it; in fullscreen,
  # crossing this hands the screen back and the *exit* raises it, but only past the
  # completion mark. Set below that and the fullscreen path stops raising the card at all,
  # silently, which is the failure this floor exists to prevent.
  UP_NEXT_RANGE = (UserEntry::COMPLETION_FRACTION..1.0).freeze

  validates :access_mode, inclusion: { in: ACCESS_MODES }
  validates :up_next_fraction, numericality: {
    greater_than_or_equal_to: UP_NEXT_RANGE.begin,
    less_than_or_equal_to: UP_NEXT_RANGE.end
  }
  # One row, ever. Every reader takes `first`, so a second row would be settings nobody
  # can see and an edit that appears to do nothing.
  validate :only_row, on: :create

  # The one row. Created on first read so a fresh database needs no seed, and memoised per
  # request through Current.
  def self.current
    Current.app_setting ||= first || create!
  end

  def self.access_mode
    current.access_mode
  end

  ACCESS_MODES.each do |mode|
    define_method(:"#{mode}?") { access_mode == mode }
  end

  def self.up_next_fraction = current.up_next_fraction

  # The form talks in percentages, because "98% of the way through" is a thing you can
  # picture and 0.98 is not.
  def up_next_percent = (up_next_fraction * 100).round(1)

  # What the setting means for a film of a given length, for the dashboard to say out loud:
  # the same percentage is two and a half minutes of a feature and twenty seconds of an
  # episode, and the number on its own hides that.
  def up_next_seconds_before_end(runtime_minutes)
    (runtime_minutes * 60 * (1 - up_next_fraction)).round
  end

  # A write invalidates the memo, so the rest of the request sees what it just saved.
  def self.update_access_mode!(mode)
    current.update!(access_mode: mode).tap { Current.app_setting = nil }
  end

  def self.update_up_next_percent!(percent)
    current.update!(up_next_fraction: percent.to_f / 100).tap { Current.app_setting = nil }
  end

  private

  def only_row
    errors.add(:base, 'The site has one row of settings and it already exists') if AppSetting.exists?
  end
end
