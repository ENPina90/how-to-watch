# frozen_string_literal: true

class ListsController < ApplicationController
  before_action :set_list, only: [:show, :edit, :destroy, :watch_current, :watch_random, :top_entries]

  def index
    @lists = List.order(:last_watched_at).reverse
    List.where(ordered: false).each{|unordered_list| unordered_list.assign_current(:next) }
  end

  def new
    @list = List.new
  end

  def create
    # @list = current_user.lists.build(list_params)
    @list = List.new(list_params)
    @list.user = current_user
    @list.current = 0
    if @list.save
      redirect_to lists_path, notice: 'List was successfully created.'
    else
      render :new
    end
  end

  def show
    load_entries
    @minimal = params[:view] == "minimal"
    @current = @list.find_entry_by_position(:current) unless @list.entries.empty?
    @random_selection = @list_entries.sample(3)
    respond_to do |format|
      format.html
      format.text do
        render partial: 'entries',
               locals: {
                 minimal: @minimal,
                 entries: @entries,
                 sections: @sections,
                 random_selection: @random_selection,
                 list_entries: @list_entries
               },
               formats: [:html]
      end
    end
  end

  def edit; end

  def destroy
    @list.destroy
    redirect_to root_path, notice: "#{@list.name} was successfully destroyed."
  end

  def watch_current
    if @list.entries.empty?
      redirect_to list_path(@list) if @list.entries.empty?
    else
      @list.update(current: @list.entries.first.position) if @list.current.nil?
      redirect_to watch_entry_path(@list.find_entry_by_position(:current))
    end
  end

  def top_entries
    tmdb_service = TmdbService.new
    series_imdb_id = tmdb_service.fetch_imdb_id(params[:tmdb], 'show')
    scraper = ImdbScraper.new(@list, series_imdb_id)
    episodes = scraper.fetch_episode_imdb_ids_with_ratings
    counter = 0
    episodes.each do |episode|
      break if counter == params[:top_number].to_i || counter == 20
      omdb_result = OmdbApi.get_movie(episode[:imdb_id])
      next if omdb_result.nil?
      next if !!(omdb_result["Title"] =~ /\s[Pp]art\s/)
      omdb_result["seriesID"] = series_imdb_id
      omdb_result["imdbRating"] = episode[:rating]
      @entry = Entry.create_from_source(omdb_result, @list, false)
      @entry.update(series: scraper_results[:title]) if @entry.series.nil?
      counter += 1
    end
    flash[:notice] = "#{ActionController::Base.helpers.pluralize(counter, 'episode')} of #{@list.entries.last&.series} added"
    redirect_to list_path(@list)
  end

  # def watch_random
  #   watch_path(@list.find_entry_by_position(:random))
  # end

  private

  def set_list
    @list = List.find(params[:id] || params[:list_id])
  end

  def load_entries
    @list_entries = if params[:query].present?
                      @list.entries.search_by_input(params[:query])
                    else
                      @list.entries
                    end
    @entries = {}
    @criteria = params[:criteria].present? ? params[:criteria] : 'Position'
    filter_entries(@criteria)
     @entries = @entries.transform_keys { |key| key.nil? ? 'Other' : key }
    @sections = params[:sort].present? ? @entries.keys.sort.reverse : @entries.keys.sort

    return unless @list.user == current_user

    @list.update(settings: params[:criteria], sort: params[:sort])
  end

  def filter_entries(criteria)
    case criteria
    when 'Genre'
      genres = @list_entries.flat_map { |entry| entry.genre.split(',').map(&:strip) }.uniq.sort
      genres.each do |genre|
        @entries[genre] = @list_entries.select { |entry| entry.genre.include?(genre) }
      end
    when 'Year'
      (1900..Date.today.year).step(10) do |year|
        decade_entries = @list_entries.select { |entry| entry.year >= year && entry.year < year + 10 }
        @entries["#{year}s"] = decade_entries unless decade_entries.empty?
      end
    when 'Watched'
      @entries['Unwatched'] = @list_entries.reject(&:completed).sort_by(&:position)
      @entries['Watched'] = @list_entries.select(&:completed).sort_by(&:position)
    else
      @entries = @list_entries.group_by { |entry| entry.send(criteria.downcase) }
    end
  end

  def list_params
    params.require(:list).permit(:name, :ordered, :private, :sort)
  end
end
