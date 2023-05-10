class ListsController < ApplicationController
  def index
    @lists = List.all
  end

  def show
    @list = List.find(params[:id])
    @list_entries = @list.entries
    @entries = {}
    filter
    @sections = @entries.keys.sort
    @random_selection = @list_entries.sample(3)
  end

  private

  def filter
    case params[:criteria]
    when "Genre"
      genres = @list_entries.group_by(&:genre).keys.map(&:split).flatten.map { |genre| genre.tr(',', '') }.uniq.sort
      genres.each do |genre|
        @entries[genre] = @list_entries.select { |entry| entry.genre.include?(genre) }
      end
    when "Year"
      # crit = params[:criteria].downcase.to_sym
      year = 1900
      until year >= Date.today.year
        decade_entries = @list_entries.select { |entry| entry.year >= year && entry.year < year + 10 }
        @entries[year] = decade_entries unless decade_entries.empty?
        year += 10
      end
    when "Watched"
      @entries['Unwatched'] = @list_entries.reject(&:completed)
      @entries['Watched'] = @list_entries.select(&:completed)
    when nil
      @entries = @list_entries.sort_by(&:created_at).group_by(&:media)
    else
      crit = params[:criteria].downcase.to_sym
      @entries = @list_entries.group_by(&crit)
    end
  end
end
