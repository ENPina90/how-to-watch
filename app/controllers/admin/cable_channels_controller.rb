# frozen_string_literal: true

module Admin
  # Which channels are on the cable dial, and in what order.
  #
  # All three actions write one column each -- `default` and `cable_position` -- and none of
  # them touches the channel itself. Taking a channel off the dial is not deleting anybody's
  # list, and there is deliberately no action here that could be mistaken for it: `destroy`
  # is named for the thing it destroys, which is the channel's place on the dial.
  #
  # The work is in CableSchedule, next to the code that reads these columns, because both
  # writes have consequences that are not obvious from the column name -- see add_channel!
  # and remove_channel! for what they are.
  class CableChannelsController < BaseController
    before_action :set_list, only: :destroy

    def create
      list = List.find_by(id: params[:list_id])

      # A private channel on the dial would show every account a list its owner chose not
      # to share, so the check is here as well as on the select: the form is a dropdown of
      # public channels, and an id typed past it should not be the way around that.
      if list.nil? || list.private?
        return redirect_to admin_cable_path, alert: 'Pick a public channel to put on the dial.'
      end

      return redirect_to admin_cable_path, notice: "#{list.name} is already on the dial." if list.default?

      CableSchedule.add_channel!(list)

      redirect_to admin_cable_path,
                  notice: "#{list.name} is on the dial, at the end of it, and today is laid out."
    end

    def destroy
      CableSchedule.remove_channel!(@list)

      redirect_to admin_cable_path,
                  notice: "#{@list.name} is off the dial. Nothing was deleted, and nobody was " \
                          'unsubscribed from it.'
    end

    # Persists a drag. The whole order arrives at once -- see CableSchedule.reorder_dial!.
    def reorder
      CableSchedule.reorder_dial!(params.require(:ids))

      head :no_content
    end

    private

    # Scoped to the dial rather than to every list, so this cannot be pointed at a channel
    # that was never on it.
    def set_list
      @list = CableSchedule.channels.find_by(id: params[:id])

      return if @list

      redirect_to admin_cable_path, alert: 'That channel is not on the dial.'
    end
  end
end
