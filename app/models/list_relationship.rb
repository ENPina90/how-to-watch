# frozen_string_literal: true

class ListRelationship < ApplicationRecord
  belongs_to :parent_list, class_name: 'List'
  belongs_to :child_list, class_name: 'List'

  validates :parent_list_id, presence: true
  validates :child_list_id, presence: true
  validates :child_list_id, uniqueness: { scope: :parent_list_id }
  validate :prevent_self_relationship
  validate :prevent_circular_relationship

  scope :ordered, -> { order(:position) }

  private

  def prevent_self_relationship
    if parent_list_id == child_list_id
      errors.add(:child_list, "cannot be the same as parent list")
    end
  end

  def prevent_circular_relationship
    return unless parent_list && child_list

    if child_list.is_ancestor_of?(parent_list)
      errors.add(:child_list, "would create a circular reference")
    end
  end
end
