# frozen_string_literal: true

# One browser on one day. Requests roll into the day's row rather than each making their
# own, so the table grows with the audience rather than with the traffic.
class Visit < ApplicationRecord
  belongs_to :user, optional: true

  validates :visitor_token, presence: true
  validates :visited_on, presence: true

  scope :since, ->(date) { where(visited_on: date..) }

  # Counts this request. One statement: the row is created the first time a browser is seen
  # that day and incremented every time after, without a read to find out which case it is.
  # `user_id` is set on the way in and refreshed on a later request, so a visit that starts
  # signed out and then signs in counts as a member for the day.
  def self.record!(visitor_token:, user_id: nil, on: Date.current)
    upsert(
      { visitor_token: visitor_token, visited_on: on, page_views: 1, user_id: user_id,
        created_at: Time.current, updated_at: Time.current },
      unique_by: %i[visitor_token visited_on],
      on_duplicate: Arel.sql(
        'page_views = visits.page_views + 1, ' \
        'user_id = COALESCE(EXCLUDED.user_id, visits.user_id), ' \
        'updated_at = EXCLUDED.updated_at'
      )
    )
  end
end
