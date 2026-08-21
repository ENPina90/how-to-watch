# frozen_string_literal: true

class List < ApplicationRecord

  belongs_to :user
  belongs_to :provider, class_name: 'Source', optional: true

  # Many-to-many relationships through list_relationships
  has_many :parent_relationships, class_name: 'ListRelationship', foreign_key: 'child_list_id', dependent: :destroy
  has_many :parent_lists, through: :parent_relationships, source: :parent_list

  has_many :child_relationships, class_name: 'ListRelationship', foreign_key: 'parent_list_id', dependent: :destroy
  has_many :child_lists, through: :child_relationships, source: :child_list

  # Legacy support - keep for backward compatibility during transition
  belongs_to :parent_list, class_name: 'List', optional: true

  # Deleted in bulk rather than one destroy per row. #bulk_delete_entry_graph below
  # does everything Entry's destroy callbacks would have done, in a fixed number of
  # statements instead of ~11 per entry.
  has_many :entries, dependent: :delete_all
  has_many :list_user_entries, dependent: :delete_all
  has_many :users, through: :list_user_entries
  has_many :subscriptions, dependent: :destroy
  has_many :subscribers, through: :subscriptions, source: :user
  has_many :user_list_positions, dependent: :destroy

  validates :preferred_source, inclusion: { in: [1, 2] }, allow_nil: true

  # Runs ahead of every dependent callback (prepend) so the whole entry graph is
  # cleared before `entries` is bulk-deleted out from under it.
  before_destroy :bulk_delete_entry_graph, prepend: true
  # Remote files are released only once the delete has actually committed.
  after_destroy_commit :purge_detached_posters

  # Auto-subscription callbacks
  after_create :auto_subscribe_owner
  after_update :handle_default_subscription_changes
  after_update :handle_privacy_subscription_changes

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
      # Find subscribed lists that have incomplete entries for this user
      lists = List.joins(:subscriptions)
                  .joins(entries: :user_entries)
                  .where(subscriptions: { user: user })
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

  # Normalize entry positions to be sequential (1, 2, 3, 4...)
  def normalize_entry_positions!
    entries.order(:position).each_with_index do |entry, index|
      new_position = index + 1
      if entry.position != new_position
        entry.update_column(:position, new_position)
      end
    end
  end

  # READ. nil when this user has never opened the list. Rendering the index page calls
  # this once per card, so it must not write -- use #position_for_user! when the user
  # actually moves.
  def position_for_user(user)
    return nil unless user

    user_list_positions.find_by(user: user)
  end

  # WRITE. Creates the tracker, starting at the first entry's position (not always 1).
  def position_for_user!(user)
    user_list_positions.find_or_create_by(user: user) do |position|
      first_entry = entries.order(:position).first
      position.current_position = first_entry&.position || 1
    end
  end

  # Get the current entry for a specific user
  def current_entry_for_user(user)
    current_position = position_for_user(user)&.current_position
    # No stored position yet: show the start of the list without recording anything.
    return entries.order(:position).first if current_position.nil?

    # The stored position can point at a deleted entry, so fall forward to the next one
    # and finally to the first. The repair is left to whichever action actually moves the
    # user (see `rails positions:fix_invalid` for a bulk pass).
    entries.find_by(position: current_position) ||
      entries.where('position >= ?', current_position).order(:position).first ||
      entries.order(:position).first
  end

  # Primary method to get current entry
  # For ordered lists: returns exact current position
  # For unordered lists: returns random incomplete entry
  def current_entry(user)
    return nil unless user
    return nil unless persisted? # Can't have positions for unsaved lists

    if ordered?
      # Ordered lists: show exact current position
      current_entry_for_user(user)
    else
      # Unordered lists: show random incomplete entry (shuffles each time)
      find_random_incomplete_entry_for_user(user) || current_entry_for_user(user)
    end
  end

  # Find next incomplete entry for a user starting from a specific position
  def find_next_incomplete_entry_for_user(user, start_position = nil)
    start_pos = start_position || position_for_user(user)&.current_position || 0

    entries.where('entries.position > ?', start_pos)
           .where.not(id: completed_entry_ids_for(user))
           .order(:position)
           .first
  end

  # Find random incomplete entry for a user (for unordered lists)
  def find_random_incomplete_entry_for_user(user, exclude_entry = nil)
    incomplete_entries = entries.where.not(id: completed_entry_ids_for(user))
    incomplete_entries = incomplete_entries.where.not(id: exclude_entry.id) if exclude_entry

    # Pick in the database. This used to load every incomplete entry and call #sample on
    # the array, which is the whole list for anyone who has not watched much.
    incomplete_entries.order(Arel.sql('RANDOM()')).first
  end

  # Advance user's position based on list type
  def advance_user_position!(user)
    user_position = position_for_user!(user)

    if ordered?
      user_position.advance_to_next!
    else
      user_position.advance_to_random!
    end
  end

  # Entry ids this user has marked complete. Kept as a relation so callers can use it as a
  # subquery rather than loading ids into Ruby.
  #
  # The previous left_joins/OR version asked "row is absent OR this user's row says
  # incomplete", which mismatched whenever *another* user had a row for the entry: the
  # absent-row branch failed and this user's branch had nothing to match, so the entry was
  # silently treated as watched and skipped.
  def completed_entry_ids_for(user)
    return UserEntry.none.select(:entry_id) unless user

    UserEntry.where(user: user, completed: true).select(:entry_id)
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

  # Get subscription count
  def subscriber_count
    subscriptions.count
  end

  private

  # Everything Entry#destroy would have done for each of this list's entries, done
  # once for the whole set. Ordered so no FK is left dangling: references into the
  # subentries first, then into the entries, then the rows themselves. Every scope is
  # a subquery over `entries`, which is still intact -- the bulk delete of `entries`
  # itself is the dependent callback that runs after this one.
  def bulk_delete_entry_graph
    entry_ids = entries.select(:id)
    subentry_ids = Subentry.where(entry_id: entry_ids).select(:id)

    UserEntryPosition.where(current_subentry_id: subentry_ids).update_all(current_subentry_id: nil)
    Entry.where(current_id: subentry_ids).update_all(current_id: nil)
    ListUserEntry.where(current_entry_id: entry_ids).update_all(current_entry_id: nil)

    # has_one_attached :poster purges per record on destroy; delete_all skips that, so
    # detach here and hold the blob ids for the post-commit purge.
    attachments = ActiveStorage::Attachment.where(record_type: 'Entry', record_id: entry_ids)
    @detached_blob_ids = attachments.pluck(:blob_id)
    attachments.delete_all

    Subentry.where(entry_id: entry_ids).delete_all
    UserEntry.where(entry_id: entry_ids).delete_all
    UserEntryPosition.where(entry_id: entry_ids).delete_all
  end

  # Deliberately after commit: a rolled-back delete must not purge live files.
  def purge_detached_posters
    return if @detached_blob_ids.blank?

    ActiveStorage::Blob.where(id: @detached_blob_ids).find_each(&:purge_later)
  end

  # Auto-subscribe the owner when creating a list
  def auto_subscribe_owner
    # Owner is always subscribed to their own lists (even private ones)
    Subscription.create_subscription(user, self, 'list owner')

    # If list is public, it will be handled by auto_subscribe_to_own_list
    # If list is default, it will be handled by auto_subscribe_to_default_list
    if default?
      Subscription.auto_subscribe_to_default_list(self)
    end
  end

  # Handle changes to default status
  def handle_default_subscription_changes
    if saved_change_to_default?
      if default?
        # List became default - subscribe all users
        Subscription.auto_subscribe_to_default_list(self)
      end
      # Note: We don't unsubscribe when removing default status
      # Users can manually unsubscribe if they want
    end
  end

  # Handle changes to privacy status
  def handle_privacy_subscription_changes
    if saved_change_to_private?
      if !private? && !default?
        # List became public (and not default) - subscribe owner if not already
        Subscription.auto_subscribe_to_own_list(user, self)
      end
      # Note: We don't unsubscribe when making private
      # Existing subscribers can keep their subscription
    end
  end
end
