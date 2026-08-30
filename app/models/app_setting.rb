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

  validates :access_mode, inclusion: { in: ACCESS_MODES }
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

  # A write invalidates the memo, so the rest of the request sees what it just saved.
  def self.update_access_mode!(mode)
    current.update!(access_mode: mode).tap { Current.app_setting = nil }
  end

  private

  def only_row
    errors.add(:base, 'The site has one row of settings and it already exists') if AppSetting.exists?
  end
end
