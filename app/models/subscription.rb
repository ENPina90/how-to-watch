# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :list

  validates :user_id, presence: true
  validates :list_id, presence: true
  validates :user_id, uniqueness: { scope: :list_id }

  scope :recent, -> { order(subscribed_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_list, ->(list) { where(list: list) }

  # Auto-subscribe user to appropriate lists
  def self.auto_subscribe_user(user)
    # Subscribe to all default lists
    default_lists = List.where(default: true)
    default_lists.each do |list|
      create_subscription(user, list, 'default list')
    end

    # Subscribe to all their own non-private lists
    own_public_lists = user.lists.where(private: false)
    own_public_lists.each do |list|
      create_subscription(user, list, 'own public list')
    end
  end

  # Auto-subscribe users to a new default list
  def self.auto_subscribe_to_default_list(list)
    return unless list.default?

    User.find_each do |user|
      create_subscription(user, list, 'new default list')
    end
  end

  # Auto-subscribe user to their own new public list
  def self.auto_subscribe_to_own_list(user, list)
    return if list.private?

    create_subscription(user, list, 'own new list')
  end

  def self.create_subscription(user, list, reason = nil)
    return if exists?(user: user, list: list)

    create!(
      user: user,
      list: list,
      subscribed_at: Time.current
    )

    Rails.logger.info "Auto-subscribed user #{user.id} to list #{list.id} (#{reason})" if reason
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "Failed to auto-subscribe user #{user.id} to list #{list.id}: #{e.message}"
  end
end
