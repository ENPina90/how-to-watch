# frozen_string_literal: true

# Deleting, editing or marking watched several entries at once, from the checkboxes in a
# channel's minimal view. One request and one confirmation for the lot, rather than a pen
# and a trash can per row -- tidying a two-hundred-episode import one "Are you sure?" at a
# time is what this replaces.
#
# The edit and the delete are all or nothing. Half a bulk edit is worse than none: the page
# would show some rows changed and some not, with nothing to say which, and the only way to
# find out would be to open each one.
#
# Marking watched is the odd one out and deliberately so: `completed` is per person, living
# in UserEntry, so it writes this member's own progress and changes nothing anybody else
# sees. There is nothing there to be left half-done that pressing it again would not put
# right, and a row already watched is left alone rather than restamped with today's date.
class BulkEntriesController < ApplicationController
  # What a bulk edit may set. Everything on the entry edit form except:
  #
  #   * the name, which is what tells entries apart -- the same name on every row is never
  #     what anyone meant, and the uniqueness check would refuse it besides;
  #   * the position, since several entries cannot all stand in the same place;
  #   * the poster upload and fetch, which download and store a file per entry. The linked
  #     poster URL is here, and costs nothing to repeat.
  EDITABLE_FIELDS = %i[list_id media length source_url provider_id source_key pic
                       series plot imdb category note season episode].freeze

  # A blank select means "leave it alone", so putting the provider back to the channel's
  # default needs a value of its own.
  INHERIT_PROVIDER = 'inherit'

  before_action :set_list
  before_action :set_entries

  def update
    changes = requested_changes
    return back_to_list(alert: 'Nothing to change: fill in at least one field.') if changes.empty?

    target = List.find_by(id: changes[:list_id]) if changes.key?(:list_id)
    if changes.key?(:list_id) && !(target && current_user.can_edit_list?(target))
      return back_to_list(alert: 'You cannot move entries into that channel.')
    end

    failed = apply(changes, target)
    if failed
      return back_to_list(alert: "Nothing was changed: #{failed.name} -- #{failed.errors.full_messages.to_sentence}")
    end

    back_to_list(notice: "Updated #{helpers.pluralize(@entries.size, 'entry')}")
  end

  def destroy
    Entry.transaction { @entries.each(&:destroy!) }

    back_to_list(notice: "Deleted #{helpers.pluralize(@entries.size, 'entry')} from #{@list.name}")
  end

  # Marking the ticked rows watched, for whoever pressed the button.
  #
  # Rows already watched are counted but not written again: `mark_completed!` stamps
  # `completed_at`, and restamping would drag a film watched last year to the top of
  # "recently completed" for no better reason than having been inside a selection.
  #
  # The count says so, because a selection that changed less than it looked like it would is
  # worth hearing about: ticking a whole season to catch the two nobody had marked should
  # report two, not twenty-two.
  def complete
    unwatched = @entries.reject { |entry| entry.completed_by?(current_user) }
    unwatched.each { |entry| entry.mark_completed_by!(current_user) }

    already = @entries.size - unwatched.size
    notice = "Marked #{helpers.pluralize(unwatched.size, 'entry')} as watched"
    notice += " (#{already} already #{already == 1 ? 'was' : 'were'})" if already.positive?

    back_to_list(notice: notice)
  end

  # Dropping several ticked rows at once. They land together, in the order they already had,
  # straight after `after_id` -- or at the top when there is none -- and everything that
  # followed that entry moves down to make room.
  #
  # Anchored to a neighbour rather than given a number, because the page's numbering is not
  # the channel's: the minimal view counts the channels mixed in among the entries, a search
  # shows only some of the rows, and a reversed sort runs the whole thing backwards. "After
  # this entry, as the page showed it" means the same thing in all three.
  def move
    unless @entries.all? { |entry| entry.list_id == @list.id }
      return refuse('Only this channel’s own entries can be reordered here.', status: :forbidden)
    end

    moving_ids = @entries.map(&:id)
    ordered_ids = @list.entries.order(:position, :id).pluck(:id)
    staying_ids = ordered_ids - moving_ids

    after_id = params[:after_id].presence&.to_i
    return refuse('That is not a place in this channel.') if after_id && !staying_ids.include?(after_id)

    reorder!(place(staying_ids, ordered_ids & moving_ids, after_id, params[:direction] == 'desc'))

    head :ok
  end

  private

  def set_list
    @list = List.find(params[:list_id])
  end

  # Only entries the page could have shown a checkbox for: this channel's, or -- when a
  # search borrowed them -- a channel's inside it, and each one this user may edit. An id
  # outside that refuses the whole request rather than quietly doing the rest, so a stale
  # page cannot report a success that skipped something.
  def set_entries
    ids = Array(params[:entry_ids]).compact_blank.uniq
    @entries = @list.entries_with_descendants.where(id: ids).includes(list: :user).order(:position).to_a

    return refuse('Select at least one entry first.') if @entries.empty?
    return if @entries.size == ids.size && @entries.all? { |entry| current_user.can_edit_entry?(entry) }

    refuse('Some of those entries are not yours to change, so nothing was.', status: :forbidden)
  end

  # The new order, as ids from the top. Worked out in the order the page showed, then turned
  # back round if the page was running backwards: on a reversed page "after" is higher up the
  # channel, and the dropped rows read bottom-to-top.
  def place(staying_ids, moving_ids, after_id, descending)
    shown = descending ? staying_ids.reverse : staying_ids
    carried = descending ? moving_ids.reverse : moving_ids
    at = after_id ? shown.index(after_id) + 1 : 0

    placed = shown.dup.insert(at, *carried)
    descending ? placed.reverse : placed
  end

  # Numbers the whole channel 1..N in the new order, touching only the rows whose number
  # changes. The whole channel rather than the rows that moved, since ties and gaps left by
  # imports and deletes would otherwise survive around them.
  def reorder!(new_order)
    positions = @list.entries.pluck(:id, :position).to_h

    Entry.transaction do
      new_order.each_with_index do |id, index|
        Entry.where(id: id).update_all(position: index + 1) unless positions[id] == index + 1
      end
    end
  end

  # A drag is sent by fetch, which follows a redirect and reads the page it lands on as a
  # success -- so a refused drag answers with a bare status the caller can see. The forms get
  # the page back with the reason on it.
  def refuse(message, status: :unprocessable_entity)
    return head(status) if action_name == 'move'

    back_to_list(alert: message)
  end

  # The fields somebody actually filled in. The modal opens empty, so a blank field is one
  # nobody touched -- which also means a bulk edit cannot clear a field, only set it.
  def requested_changes
    fields = params.fetch(:entry, {}).permit(*EDITABLE_FIELDS).to_h.symbolize_keys
    changes = fields.reject { |_field, value| value.to_s.strip.empty? }
    changes[:provider_id] = nil if changes[:provider_id] == INHERIT_PROVIDER
    changes
  end

  # Returns the entry that refused, or nil when every one saved.
  #
  # A move goes to the end of the other channel, in the order the entries had here. Keeping
  # their old numbers would put them on top of whatever already holds those positions there.
  def apply(changes, target)
    failed = nil

    Entry.transaction do
      next_position = target && Entry.next_position(target)

      @entries.each do |entry|
        attributes = changes.dup
        if target && entry.list_id != target.id
          attributes[:position] = next_position
          next_position += 1
        else
          attributes.delete(:list_id)
        end

        next if entry.update(attributes)

        failed = entry
        raise ActiveRecord::Rollback
      end
    end

    failed
  end

  # Back to the page the checkboxes were on, search and all. 303 because these are PATCH and
  # DELETE: fetch repeats the method on a 302, and Turbo would issue a DELETE to the list.
  def back_to_list(**flash)
    redirect_back fallback_location: list_path(@list, view: 'minimal'), status: :see_other, **flash
  end
end
