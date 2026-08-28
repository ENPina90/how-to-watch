# frozen_string_literal: true

# A vote from one device. `voter_token` is a random value in that device's own cookie --
# there is no account behind it, and nothing is asked of whoever scanned the code.
class Vote < ApplicationRecord
  belongs_to :vote_session
  belongs_to :vote_option

  validates :voter_token, presence: true, uniqueness: { scope: :vote_session_id }

  before_validation :inherit_session_from_option

  private

  def inherit_session_from_option
    self.vote_session ||= vote_option&.vote_session
  end
end
