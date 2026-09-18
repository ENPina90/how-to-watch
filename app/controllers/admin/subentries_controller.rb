# frozen_string_literal: true

module Admin
  # Every episode under every show, as one table -- /admin/entries for the rows below the
  # entries. Name, show, season and episode, runtime, and where it plays from.
  #
  # Built the same way as that page and for the same reason: sorting done here on a
  # whitelisted column, only the displayed columns selected, one toolbar moved between rows,
  # and one modal whose frame loads a single episode's form (see Admin::EntriesController).
  #
  # Two of that page's columns have nothing to show here, and the difference is the data's,
  # not this page's. An episode has no provider of its own -- it plays from its show's, with
  # its season and episode put into the show's template -- so the source column reads the
  # show's and is not edited here. And there is no stream column, because `subentries` has
  # no `stream`: nothing has ever recorded whether one episode plays.
  class SubentriesController < BaseController
    before_action :set_subentry, only: %i[edit update destroy]

    # Each is the column or columns that sort in the direction asked for. Every sort then
    # falls back to show, season, episode, so what comes out is always in viewing order
    # within whatever was asked for.
    SORTS = {
      'name'    => ['LOWER(subentries.name)'],
      'show'    => ['LOWER(entries.name)'],
      'episode' => ['subentries.season', 'subentries.episode'],
      'length'  => ['subentries.length']
    }.freeze

    # The show's resolved provider, sorted in Ruby for the reason the entries table gives:
    # the rule lives in Entry#resolved_source, and a SQL copy would drift from it.
    SOURCE_SORT = 'source'

    VIEWING_ORDER = ['LOWER(entries.name) ASC', 'subentries.season ASC NULLS LAST',
                     'subentries.episode ASC NULLS LAST', 'subentries.id'].freeze

    COLUMNS = %w[id name entry_id season episode length].map { |column| "subentries.#{column}" }.freeze

    # By show rather than by name, unlike the entries table. A thousand episode names in
    # alphabetical order is a list nobody reads; episodes are found by the show they are in.
    def index
      @sort = SORTS.key?(params[:sort]) || params[:sort] == SOURCE_SORT ? params[:sort] : 'show'
      @direction = params[:direction] == 'desc' ? 'desc' : 'asc'
      @subentries = sorted_subentries
      @hide_sidebar = true
    end

    def edit; end

    def update
      if @subentry.update(subentry_params)
        flash.now[:notice] = "#{helpers.subentry_table_name(@subentry)} saved."
        render turbo_stream: [
          turbo_stream.replace(@subentry, partial: 'admin/subentries/row', locals: { subentry: @subentry }),
          turbo_stream.replace('flash', partial: 'shared/flashes')
        ]
      else
        # Most often the season and episode clash with another episode of the same show --
        # Subentry validates that pair unique within a show.
        render :edit, status: :unprocessable_entity
      end
    end

    # Subentry#destroy, so its own callbacks run: saved positions pointing at the episode
    # are cleared, and the show's current-episode pointer is moved off it.
    def destroy
      name = helpers.subentry_table_name(@subentry)

      if @subentry.destroy
        flash.now[:notice] = "#{name} deleted."
        streams = [turbo_stream.remove(@subentry)]
      else
        flash.now[:alert] = "#{name} could not be deleted: #{@subentry.errors.full_messages.to_sentence}"
        streams = []
      end

      respond_to do |format|
        format.turbo_stream { render turbo_stream: streams << turbo_stream.replace('flash', partial: 'shared/flashes') }
        format.html { redirect_to admin_subentries_path, notice: flash.now[:notice], alert: flash.now[:alert] }
      end
    end

    private

    def set_subentry
      @subentry = Subentry.find(params[:id])
    end

    # The show comes along whole: it is a few dozen rows however many episodes there are, and
    # resolved_source needs its provider, its channel's provider and its imdb id.
    def sorted_subentries
      scope = Subentry.joins(:entry).select(COLUMNS).preload(entry: [:provider, { list: :provider }])
      return sort_by_source(scope) if @sort == SOURCE_SORT

      sorted = SORTS.fetch(@sort).map { |column| "#{column} #{@direction.upcase} NULLS LAST" }
      scope.order(*(sorted + VIEWING_ORDER).map { |clause| Arel.sql(clause) }).to_a
    end

    # Viewing order first, then a stable sort on the provider, so each show's episodes stay in
    # order within it. Array#sort_by is not stable by itself, hence the index.
    def sort_by_source(scope)
      subentries = scope.order(*VIEWING_ORDER.map { |clause| Arel.sql(clause) }).to_a
      sorted = subentries.each_with_index
                         .sort_by { |subentry, index| [subentry.entry.resolved_source&.name.to_s.downcase, index] }
                         .map(&:first)

      @direction == 'desc' ? sorted.reverse : sorted
    end

    # What the table shows and an episode owns. Not the show it belongs to: moving an episode
    # to another show would leave the old show's current-episode pointer, and every member's
    # saved position in it, aimed at an episode that is no longer there.
    def subentry_params
      params.require(:subentry).permit(:name, :season, :episode, :length)
    end
  end
end
