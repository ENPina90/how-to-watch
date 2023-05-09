class ListsController < ApplicationController
  def index
    @lists = List.all
  end

  def show
    @list = List.find(params[:id])
    params[:criteria] = 'completed' if params[:criteria] == "Watched"
    @list_entries = @list.entries.order(params[:criteria])
    if params[:criteria] == "Genre"
      @entries = {}
      genres = @list_entries.group_by(&:genre).keys.map(&:split).flatten.map { |genre| genre.tr(',', '') }.uniq.sort
      genres.each do |genre|
        @entries[genre] = @list_entries.select { |entry| entry.genre.include?(genre) }
      end
    elsif params[:criteria] == "Year"
      # crit = params[:criteria].downcase.to_sym
      @entries = {}
      year = 1900
      until year >= Date.today.year
        decade_entries = @list_entries.select { |entry| entry.year >= year && entry.year < year + 10 }
        @entries[year] = decade_entries unless decade_entries.empty?
        year += 10
      end
    elsif params[:criteria].nil?
      @entries = {}
      @entries = @list_entries.sort_by(&:created_at).group_by(&:category)
    else
      crit = params[:criteria].downcase.to_sym
      @entries = @list_entries.group_by(&crit)
    end
    @sections = @entries.keys.sort
    # raise
    @random_selection = @list_entries.sample(3)
  end
end
