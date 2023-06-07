class ListsController < ApplicationController
  def index
    @lists = List.all
  end

  def new
    @list = List.new
  end

  def create
    @list = List.new(list_params)
    @list.user = current_user
    @list.save
    redirect_to lists_path
  end

  def show
    @list = List.find(params[:id])
    @user_lists = List.where(user: current_user)
    entries_hash
    @random_selection = @list_entries.sample(3)
    respond_to do |format|
      format.html # Follow regular flow of Rails
      format.text { render partial: "entries", locals: { entries: @entries, sections: @sections, random_selection: @random_selection, list_entries: @list_entries }, formats: [:html] }
    end
  end

  # def randomize
  #   @list = List.find(params[:list_id])
  #   entries_hash
  #   @random_selection = @list_entries.where(stream: true).sample(3)
  #   render partial: "upnext", locals: { random_selection: @random_selection }
  # end

  private

  def entries_hash
    if params[:query]
      @list_entries = @list.entries.search_by_input(params[:query])
    elsif params[:query].nil? || params[:query].length <= 1
      @list_entries = @list.entries
    end
    @entries = {}
    filter
    @sections = @entries.keys.sort
  end

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

  def list_params
    params.require(:list).permit(:name)
  end
end
