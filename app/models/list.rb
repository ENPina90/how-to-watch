# frozen_string_literal: true

class List < ApplicationRecord

  belongs_to :user

  # Many-to-many relationships through list_relationships
  has_many :parent_relationships, class_name: 'ListRelationship', foreign_key: 'child_list_id', dependent: :destroy
  has_many :parent_lists, through: :parent_relationships, source: :parent_list

  has_many :child_relationships, class_name: 'ListRelationship', foreign_key: 'parent_list_id', dependent: :destroy
  has_many :child_lists, through: :child_relationships, source: :child_list

  # Legacy support - keep for backward compatibility during transition
  belongs_to :parent_list, class_name: 'List', optional: true

  has_many :entries, dependent: :destroy
  has_many :list_user_entries
  has_many :users, through: :list_user_entries

  OFFSET = {
      previous: -1,
      current:   0,
      next:      1,
      # random:    rand(0...self.list.entries.count)
    }

  def self.like(name)
    where('name ILIKE ?', "%#{name}%").first
  end

  def watched!(user = nil)
    entry = find_next_incomplete_entry(user)
    self.update(current: entry&.position || current)
  end

  def find_entry_by_position(change, user = nil)
    return nil if entries.empty?

    # Determine the starting position.
    new_position = OFFSET.key?(change) ? current.to_i + OFFSET[change] : change.to_i

    # Ensure new_position falls within the min/max bounds of entry positions.
    min_position = entries.minimum(:position)
    max_position = entries.maximum(:position)
    new_position = min_position if new_position < min_position || new_position > max_position

    # Loop until we find a valid, not completed entry or exceed the maximum bound.
    while new_position <= max_position
      entry = entries.find_by(position: new_position)
      if entry
        # Check per-user completion if user provided, otherwise use old system
        completed = user ? entry.completed_by?(user) : entry.completed
        return entry if !completed
      end
      new_position += 1
    end

    # Return nil if no valid entry is found.
    nil
  end


  def assign_current(change, user = nil)
    if OFFSET.key?(change)
      # For relative changes (:next, :previous, :current), just move sequentially
      current_pos = current || 1  # Default to 1 if current is nil
      new_position = current_pos + OFFSET[change]

      # Ensure new_position falls within the min/max bounds of entry positions
      min_position = entries.minimum(:position) || 1
      max_position = entries.maximum(:position) || 1

      if new_position < min_position
        new_position = min_position
      elsif new_position > max_position
        new_position = max_position
      end

      # Find the entry at this position
      entry = entries.find_by(position: new_position)
      if entry
        update(current: new_position)
        return entry
      else
        # No entry at exact position, find closest entry or stay at current
        closest_entry = entries.where('position >= ?', new_position).order(:position).first ||
                       entries.where('position <= ?', new_position).order(position: :desc).first
        if closest_entry
          update(current: closest_entry.position)
          return closest_entry
        else
          return entries.find_by(position: current_pos)
        end
      end
    else
      # For absolute position changes
      new_position = change.to_i
      update(current: new_position)
      Entry.find_by(list: self, position: new_position)
    end
  end

  # New method for finding next incomplete entry (used by watched! method)
  def find_next_incomplete_entry(user = nil)
    return find_entry_by_position(:next, user)
  end

  def find_sibling(change, user = nil)
    if user
      # Find lists that have incomplete entries for this user
      lists = List.joins(entries: :user_entries)
                  .where(user_entries: { user: user, completed: false })
                  .distinct
                  .where.not(current: nil)
                  .order(:created_at)
    else
      # Fallback to old system
      lists = List.joins(:entries).where(entries: { completed: false }).distinct.where.not(current: nil).order(:created_at)
    end
    # lists = List.where.associated(:entries).where.not(current: nil).order(:created_at)
    current_list_index = lists.index(self)
    return lists.first unless current_list_index
    new_index = current_list_index + OFFSET[change]
    if new_index < 0
      lists.last
    elsif new_index >= lists.count
      lists.first
    else
      lists[new_index]
    end
  end

  # Get all items (entries and child lists) in position order for a specific parent context
  def all_items_by_position(parent_list = nil)
    items = entries.to_a

    if parent_list
      # Get child lists with their position in this specific parent context
      child_relationships = self.child_relationships.where(parent_list: self)
      child_lists_with_position = child_relationships.includes(:child_list).map do |rel|
        child = rel.child_list
        child.define_singleton_method(:position) { rel.position }
        child
      end
      items += child_lists_with_position
    else
      items += child_lists.to_a
    end

    items.sort_by { |item| item.position || 0 }
  end

  # Find next available position for a new item in this list
  def next_position_for_parent
    max_entry_position = entries.maximum(:position) || 0
    max_list_position = child_relationships.maximum(:position) || 0
    [max_entry_position, max_list_position].max + 1
  end

  # Check if this list can be added to the target list (prevent circular references)
  def can_be_added_to?(target_list)
    return false if target_list == self
    return false if target_list.is_descendant_of?(self)
    return false if parent_lists.include?(target_list) # Already a child of target
    true
  end

  # Check if this list is a descendant of the given list (through any path)
  def is_descendant_of?(ancestor_list)
    return false if parent_lists.empty?
    return true if parent_lists.include?(ancestor_list)
    parent_lists.any? { |parent| parent.is_descendant_of?(ancestor_list) }
  end

  # Check if this list is an ancestor of the given list
  def is_ancestor_of?(descendant_list)
    return false if child_lists.empty?
    return true if child_lists.include?(descendant_list)
    child_lists.any? { |child| child.is_ancestor_of?(descendant_list) }
  end

  # Get all ancestors of this list (returns array of arrays for multiple paths)
  def all_ancestor_paths
    return [[]] if parent_lists.empty?

    paths = []
    parent_lists.each do |parent|
      parent.all_ancestor_paths.each do |ancestor_path|
        paths << [parent] + ancestor_path
      end
    end
    paths
  end

  # Get primary ancestor path (shortest or first path)
  def primary_ancestors
    paths = all_ancestor_paths
    return [] if paths.empty?
    paths.min_by(&:length) || []
  end

  # Get all descendant lists (children, grandchildren, etc.)
  def all_descendants
    child_lists.flat_map { |child| [child] + child.all_descendants }
  end

  # Check if this list is a top-level list (has no parents)
  def top_level?
    parent_lists.empty?
  end

  # Get minimum depth in the hierarchy (0 for top-level)
  def min_depth
    return 0 if parent_lists.empty?
    parent_lists.map(&:min_depth).min + 1
  end

  # Get maximum depth in the hierarchy
  def max_depth
    return 0 if parent_lists.empty?
    parent_lists.map(&:max_depth).max + 1
  end

  # Add this list to a parent list
  def add_to_parent(parent_list)
    return false unless can_be_added_to?(parent_list)

    ListRelationship.create!(
      parent_list: parent_list,
      child_list: self,
      position: parent_list.next_position_for_parent
    )
  end

  # Remove this list from a specific parent
  def remove_from_parent(parent_list)
    parent_relationships.where(parent_list: parent_list).destroy_all
  end

  # Remove this list from all parents
  def remove_from_all_parents
    parent_relationships.destroy_all
  end
end
