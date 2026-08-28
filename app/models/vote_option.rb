# frozen_string_literal: true

# One entry on a ballot. Taking it off the ballot takes its votes with it.
class VoteOption < ApplicationRecord
  belongs_to :vote_session
  belongs_to :entry
  has_many :votes, dependent: :destroy

  validates :entry_id, uniqueness: { scope: :vote_session_id }
end
