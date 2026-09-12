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

  # How long before the end of a film the up-next countdown appears, in seconds -- and how
  # long it then counts for, so it reaches zero as the film does. One number, because two
  # of them can disagree and there is no reading of "the countdown" where they should.
  #
  # Seconds rather than the share of the runtime this used to be. A percentage is not what
  # anybody means by "just before it ends": the same 98% is two and a half minutes of a
  # feature and twenty seconds of an episode, which is the difference between a card that
  # appears over the credits and one that appears during the last scene.
  #
  # The floor -- never earlier than the completion mark -- is not here, because it cannot
  # be. Whether a lead is too long is a question about the film's length, and this setting
  # knows nothing about any particular film; see `up_next_mark_for`, which is where it is
  # applied, and player_progress_controller, which applies the same rule client-side.
  UP_NEXT_LEAD_RANGE = (5..300).freeze

  validates :access_mode, inclusion: { in: ACCESS_MODES }
  validates :up_next_lead_seconds, numericality: {
    only_integer: true,
    greater_than_or_equal_to: UP_NEXT_LEAD_RANGE.begin,
    less_than_or_equal_to: UP_NEXT_LEAD_RANGE.end
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

  def self.up_next_lead_seconds = current.up_next_lead_seconds

  # Where in a film of this length the card actually comes up, in seconds from the start.
  #
  # The lead, floored at the completion mark. Both routes to the card are gated on the film
  # counting as watched -- windowed, crossing this raises it; in fullscreen the same
  # crossing raises it over the picture -- so a mark earlier than that is a card that never
  # appears, silently. Fifteen seconds before the end of a two-minute clip is exactly that,
  # which is why the floor is here rather than in a validation: it depends on the film.
  def up_next_mark_for(runtime_seconds)
    runtime_seconds = runtime_seconds.to_f
    return nil unless runtime_seconds.positive?

    [runtime_seconds - up_next_lead_seconds, runtime_seconds * UserEntry::COMPLETION_FRACTION].max
  end

  # What the setting comes to for a film of a given length, for the dashboard to say out
  # loud. The same as the lead for anything of normal length, and less for something short
  # enough that the floor bites -- which is the case worth showing.
  def up_next_seconds_before_end(runtime_minutes)
    seconds = runtime_minutes * 60
    mark = up_next_mark_for(seconds)

    mark ? (seconds - mark).round : 0
  end

  # A write invalidates the memo, so the rest of the request sees what it just saved.
  def self.update_access_mode!(mode)
    current.update!(access_mode: mode).tap { Current.app_setting = nil }
  end

  def self.update_up_next_lead!(seconds)
    current.update!(up_next_lead_seconds: seconds).tap { Current.app_setting = nil }
  end

  private

  def only_row
    errors.add(:base, 'The site has one row of settings and it already exists') if AppSetting.exists?
  end
end
