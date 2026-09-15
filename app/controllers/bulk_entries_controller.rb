# frozen_string_literal: true

# Deleting or editing several entries at once, from the checkboxes in a channel's minimal
# view. One request and one confirmation for the lot, rather than a pen and a trash can per
# row -- tidying a two-hundred-episode import one "Are you sure?" at a time is what this
# replaces.
#
# Both actions are all or nothing. Half a bulk edit is worse than none: the page would show
# some rows changed and some not, with nothing to say which, and the only way to find out
# would be to open each one.
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

    return back_to_list(alert: 'Select at least one entry first.') if @entries.empty?
    return if @entries.size == ids.size && @entries.all? { |entry| current_user.can_edit_entry?(entry) }

    back_to_list(alert: 'Some of those entries are not yours to change, so nothing was.')
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
