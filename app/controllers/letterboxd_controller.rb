# frozen_string_literal: true

class LetterboxdController < ApplicationController
  # The sign-up form checks a handle before the account exists, so this cannot sit behind
  # authentication whatever the site's access mode is. It is a GET that reveals only
  # whether a public Letterboxd profile exists, which is already public.
  skip_before_action :authenticate_user_unless_guest_allowed!, only: :check

  # Each check is an outbound request to Letterboxd, so an open endpoint is throttled
  # rather than left as a way to make this server hammer theirs.
  rate_limit to: 20, within: 1.minute, only: :check

  # How long a verdict about a handle is trusted. Long enough that typing in the form
  # does not re-fetch on every keystroke, short enough that a member who fixes a private
  # profile is not told it is wrong for the rest of the day.
  CHECK_TTL = 10.minutes

  # How long to wait after somebody opens Letterboxd's review prompt before re-reading
  # their diary. Long enough to write and post a review, short enough that the entry shows
  # up in the app while they still remember doing it.
  REVIEW_DELAY = 10.minutes

  # Is this a Letterboxd handle with a readable diary? Answers the tick or the warning
  # next to the username field on sign-up and on the profile page.
  def check
    username = params[:username].to_s.strip

    unless LetterboxdFeed.valid_username?(username)
      return render json: {
        status: 'invalid',
        message: "A Letterboxd username is letters, numbers and underscores."
      }
    end

    if readable?(username)
      render json: { status: 'ok', message: "Found @#{username} on Letterboxd." }
    else
      render json: {
        status: 'not_found',
        message: "No public Letterboxd diary for @#{username}.",
        hint: 'Use your Letterboxd username, not your display name. A private profile cannot be read either.'
      }
    end
  end

  # Called when somebody opens the review prompt for a film. Their review will not be in
  # the feed yet, so the refresh is booked for later rather than run now.
  def reviewed
    return head :no_content unless current_user&.letterboxd_ready?

    # One pending refresh is enough. Someone working through a few films would otherwise
    # book a full diary read per click, and the first one to land covers all of them.
    if Rails.cache.write(refresh_key, true, expires_in: REVIEW_DELAY, unless_exist: true)
      LetterboxdSyncJob.set(wait: REVIEW_DELAY).perform_later(current_user.id)
    end

    head :accepted
  end

  private

  def refresh_key
    ['letterboxd-refresh-pending', current_user.id]
  end

  def readable?(username)
    Rails.cache.fetch(['letterboxd-check', username.downcase], expires_in: CHECK_TTL) do
      LetterboxdFeed.new(username).readable?
    end
  end
end
