# frozen_string_literal: true

# Counts who comes to the site, for the admin dashboard.
#
# What is recorded is deliberately thin: a random token from the visitor's own cookie, the
# day, how many pages they opened, and their user id if they were signed in. No path, no
# referrer, no address. It answers "how many people, how often" and nothing else.
module VisitTracking
  extend ActiveSupport::Concern

  # A year is long enough that a regular is one row a day rather than a new stranger every
  # week, and the token means nothing outside this table.
  TOKEN_COOKIE = :visitor_token
  TOKEN_TTL = 1.year

  included do
    after_action :record_visit
  end

  private

  def record_visit
    return unless trackable_visit?

    Visit.record!(visitor_token: visitor_token, user_id: current_user&.id)
  rescue StandardError => e
    # Analytics must never be the reason a page fails to render.
    Rails.logger.warn("Visit tracking failed: #{e.class}: #{e.message}")
  end

  # Page views only: a redirect is the same visit arriving somewhere else, a Turbo Stream is
  # a fragment of a page already counted, and the health check is Railway, not a person.
  def trackable_visit?
    request.get? &&
      response.status == 200 &&
      request.format.html? &&
      !request.xhr? &&
      action_name != 'health'
  end

  # The browser, not the person. Signed so it cannot be edited into someone else's, and
  # httponly so no script on the page can read it.
  def visitor_token
    cookies.signed[TOKEN_COOKIE] ||= {
      value: SecureRandom.uuid,
      expires: TOKEN_TTL.from_now,
      httponly: true
    }

    cookies.signed[TOKEN_COOKIE]
  end
end
