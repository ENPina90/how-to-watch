class ListsController < ApplicationController
  def index
    @lists = List.all
  end

  def show
    @list = List.find(params[:id])
    params[:criteria] = 'completed' if params[:criteria] == "Watched"
    @entries = @list.entries.order(params[:criteria])
    if params[:criteria] == "Genre"
      @entries = {}
      Entry.genres.each do |genre|
        @entries[genre] = @list.entries.select { |entry| entry.genre.include?(genre) }
      end
    else
      crit = params[:criteria].downcase.to_sym
      @entries = Entry.all.group_by(&crit)
    end
    @sections = @entries.keys.sort
    # raise
    @random_selection = @entries.values.flatten.sample(3)
  end
end
