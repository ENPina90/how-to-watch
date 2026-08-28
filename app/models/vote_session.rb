# frozen_string_literal: true

# One round of voting on a channel: a shortlist put up on a screen, and the votes phones
# cast on it. A channel has at most one round open at a time; closed rounds are kept so the
# result can still be read.
class VoteSession < ApplicationRecord
  belongs_to :list
  has_many :vote_options, -> { order(:position) }, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :entries, through: :vote_options

  scope :open, -> { where(closed_at: nil) }

  # Puts a shortlist up, replacing whatever was there. A random draw rather than the first
  # few: the point is to decide between things nobody has picked out already.
  def self.open_for(list, count)
    transaction do
      list.vote_sessions.open.find_each(&:destroy)

      session = list.vote_sessions.create!
      list.entries.to_a.sample(count).each_with_index do |entry, index|
        session.vote_options.create!(entry: entry, position: index)
      end
      session
    end
  end

  def open?
    closed_at.nil?
  end

  def close!
    update!(closed_at: Time.current) if open?
  end

  # Options with their counts, most votes first. Ties keep ballot order, so a tie reads the
  # same way twice rather than shuffling under whoever refreshes.
  def standings
    counts = votes.group(:vote_option_id).count

    vote_options.includes(:entry).map { |option| [option, counts.fetch(option.id, 0)] }
                .sort_by { |option, count| [-count, option.position] }
  end

  def winner
    leader, count = standings.first
    return nil if leader.nil? || count.zero?

    leader
  end

  def vote_for(option, token)
    # One vote per device, changeable while the round is open: a phone that taps again has
    # changed its mind rather than voted twice.
    vote = votes.find_or_initialize_by(voter_token: token)
    vote.vote_option = option
    vote.save!
    vote
  end
end
