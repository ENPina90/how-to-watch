# frozen_string_literal: true

module Admin
  # Every entry in the app as one table: name, channel, media, runtime, where it plays from,
  # and whether its stream is known to work. The view the library never had -- "what plays
  # from Drive", "what is marked broken", "what has no runtime" used to be console queries,
  # and here each is a click on a column heading.
  #
  # It is thousands of rows, and the page is built around that rather than paginated away
  # from it:
  #
  #   * sorting is done here, on a whitelisted column, so a row carries no sort keys and a
  #     sorted view is a URL that can be bookmarked;
  #   * only the columns the table shows are selected, and the two associations it reads are
  #     preloaded -- one query for the rows, one each for channels and sources;
  #   * nothing per row is a form, a modal or a copy of the entry's data. The edit form is
  #     fetched for one entry when its pencil is pressed, into a single modal on the page,
  #     and a save or a delete answers with a stream that touches that one row. Drawing the
  #     table again after every edit would cost more than the edit.
  class EntriesController < BaseController
    before_action :set_entry, only: %i[edit update destroy stream]

    # What each heading sorts by. Names are compared case-insensitively, so "the Thing"
    # does not sort after every capitalised title.
    SORTS = {
      'name'   => 'LOWER(entries.name)',
      'list'   => 'LOWER(lists.name)',
      'media'  => 'entries.media',
      'length' => 'entries.length',
      'stream' => 'entries.stream'
    }.freeze

    # Sorted in Ruby rather than SQL, because the answer belongs to Entry#resolved_source:
    # the entry's own provider, else its channel's, else the default imdb provider -- with
    # a deactivated provider skipped along the way. Writing that again as a CASE expression
    # would be a second copy of the rule, and the one that drifted would be this one. The
    # rows are all loaded to be drawn anyway, so sorting them costs nothing extra.
    SOURCE_SORT = 'source'

    # Only what the table draws and resolved_source reads. `imdb` is here for the second of
    # those: it is how an entry with no working provider of its own falls back to the
    # default imdb one.
    COLUMNS = %w[id name list_id media length provider_id source_key stream imdb]
              .map { |column| "entries.#{column}" }.freeze

    def index
      @sort = SORTS.key?(params[:sort]) || params[:sort] == SOURCE_SORT ? params[:sort] : 'name'
      @direction = params[:direction] == 'desc' ? 'desc' : 'asc'
      @entries = sorted_entries
      @hide_sidebar = true
    end

    # Answers the modal's turbo frame. Rendered with the frame layout turbo-rails picks for a
    # frame request, so this is the form and nothing around it.
    def edit
      @lists = List.order(:name).pluck(:name, :id)
    end

    def update
      if @entry.update(update_attributes)
        flash.now[:notice] = "#{@entry.name} saved."
        render turbo_stream: [
          turbo_stream.replace(@entry, partial: 'admin/entries/row', locals: { entry: @entry }),
          turbo_stream.replace('flash', partial: 'shared/flashes')
        ]
      else
        # Back into the frame with the errors against their fields. A 422 is what tells
        # the modal the save did not happen, so it stays open.
        @lists = List.order(:name).pluck(:name, :id)
        render :edit, status: :unprocessable_entity
      end
    end

    # The stream mark in the table, pressed: working becomes broken and broken becomes
    # working. The page sends the value it wants rather than asking for a flip, so a double
    # click, or a second tab showing the old mark, sets the same thing twice instead of
    # undoing itself.
    #
    # Only true or false. "Never checked" is set from the edit form -- a mark pressed says
    # somebody has now looked, which is exactly what never checked is not.
    #
    # Written straight to the column. It is one flag on a row somebody has just looked at,
    # and routing it through validation would refuse the flip on an entry whose name happens
    # to clash with another in its channel -- a problem the flag has nothing to do with.
    def stream
      value = ActiveModel::Type::Boolean.new.cast(params[:value])
      return head :unprocessable_entity if value.nil?

      @entry.update_columns(stream: value, updated_at: Time.current)
      flash.now[:notice] = "#{@entry.name} marked #{value ? 'working' : 'broken'}."
      render turbo_stream: [
        turbo_stream.replace(@entry, partial: 'admin/entries/row', locals: { entry: @entry }),
        turbo_stream.replace('flash', partial: 'shared/flashes')
      ]
    end

    # The model's own destroy, so every callback the channel page's delete relies on runs
    # here too -- the subentry references first, then the dependents.
    def destroy
      name = @entry.name

      if @entry.destroy
        flash.now[:notice] = "#{name} deleted."
        streams = [turbo_stream.remove(@entry)]
      else
        flash.now[:alert] = "#{name} could not be deleted: #{@entry.errors.full_messages.to_sentence}"
        streams = []
      end

      respond_to do |format|
        format.turbo_stream { render turbo_stream: streams << turbo_stream.replace('flash', partial: 'shared/flashes') }
        format.html { redirect_to admin_entries_path, notice: flash.now[:notice], alert: flash.now[:alert] }
      end
    end

    private

    def set_entry
      @entry = Entry.find(params[:id])
    end

    def sorted_entries
      scope = Entry.joins(:list).select(COLUMNS).preload(:provider, list: :provider)
      return sort_by_source(scope) if @sort == SOURCE_SORT

      # Blanks last in both directions: a column of empty runtimes is not what somebody
      # sorting by runtime is looking for, whichever way round they asked. Name breaks ties
      # so rows with the same channel or media still read in an order, and the id makes it
      # the same order every time.
      scope.order(Arel.sql("#{SORTS.fetch(@sort)} #{@direction.upcase} NULLS LAST"),
                  Arel.sql('LOWER(entries.name) ASC'), 'entries.id').to_a
    end

    # Name order first, then a stable sort on the provider, so entries on the same provider
    # stay alphabetical. Array#sort_by is not stable by itself, hence the index.
    def sort_by_source(scope)
      entries = scope.order(Arel.sql('LOWER(entries.name) ASC'), 'entries.id').to_a
      sorted = entries.each_with_index
                      .sort_by { |entry, index| [entry.resolved_source&.name.to_s.downcase, index] }
                      .map(&:first)

      @direction == 'desc' ? sorted.reverse : sorted
    end

    # Only what the table shows, plus a pasted link as the quick way to change where it
    # plays from. A pasted link wins over the provider and key fields -- Entry#apply_source_url
    # sets both from it before validation.
    def entry_params
      params.require(:entry).permit(:name, :list_id, :media, :length, :provider_id,
                                    :source_key, :source_url, :stream)
    end

    # A move to another channel goes to the end of it, the same as the channel page's edit
    # form does: the entry's position is a place in the channel it is leaving, and keeping
    # it would land on top of whatever holds that number in the new one.
    #
    # A cleared source key is stored as NULL, not as the empty string a blank text field
    # submits: 2,900 entries have no key and read NULL, and a handful of "" among them would
    # make "has no key" a two-part question for every query that asks it.
    def update_attributes
      attributes = entry_params.to_h
      attributes['source_key'] = attributes['source_key'].presence if attributes.key?('source_key')
      destination_id = attributes.delete('list_id')
      return attributes if destination_id.blank? || destination_id.to_i == @entry.list_id

      destination = List.find(destination_id)
      attributes.merge('list' => destination, 'position' => Entry.next_position(destination))
    end
  end
end
