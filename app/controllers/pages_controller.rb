class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home ]

  def home
  end

  def watch_now
    @imdb_id = params[:imdb]&.strip
    @title = params[:title]&.strip || 'Movie'
    @media_type = params[:type]&.strip || 'movie'
    @poster = params[:poster]&.strip

    # Validate imdb_id format (should be tt followed by digits)
    unless @imdb_id.present? && @imdb_id.match(/^tt\d+$/)
      redirect_to root_path, alert: 'Invalid movie ID'
      return
    end

    # Validate media type (should be 'movie' or 'tv')
    unless ['movie', 'tv'].include?(@media_type)
      @media_type = 'movie' # Default to movie if invalid type
    end

    # Sanitize title (remove any HTML tags and limit length)
    @title = ActionController::Base.helpers.strip_tags(@title).truncate(100)

    # Use placeholder if no poster provided
    @poster = @poster.present? ? @poster : '/images/please_stand_by.png'
  end
end
