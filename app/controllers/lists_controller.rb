# frozen_string_literal: true

class ListsController < ApplicationController
  before_action :set_list, only: [:show]

  def index
    @lists = List.all
  end

  def new
    @list = List.new
  end

  def create
    @list = current_user.lists.build(list_params)
    if @list.save
      redirect_to lists_path, notice: 'List was successfully created.'
    else
      render :new
    end
  end

  def show
    load_entries
    @random_selection = @list_entries.sample(3)
    respond_to do |format|
      format.html
      format.text do
        render partial: 'entries',
               locals: {
                 entries: @entries,
                 sections: @sections,
                 random_selection: @random_selection,
                 list_entries: @list_entries
               },
               formats: [:html]
      end
    end
  end

  private

  def set_list
    @list = List.find(params[:id])
  end

  def list_params
    params.require(:list).permit(:name)
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
      @entries['Unwatched'] = @list_entries.reject(&:completed)
      @entries['Watched'] = @list_entries.select(&:completed)
    else
      @entries = @list_entries.group_by { |entry| entry.send(criteria.downcase) }
    end
  end
end
