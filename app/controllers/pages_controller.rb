require 'open-uri'
require 'json'

class PagesController < ApplicationController
  def watch_now
    @imdb_id = params[:imdb]&.strip
    @title = params[:title]&.strip || 'Movie'
    @media_type = params[:type]&.strip || 'movie'
    @poster = params[:poster]&.strip
    @tmdb_id = params[:tmdb]&.strip
    @season = params[:season].present? ? params[:season].strip.to_i : nil
    @episode = params[:episode].present? ? params[:episode].strip.to_i : nil

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

    # For TV shows, fetch episode data
    if @media_type == 'tv'
      tmdb = TmdbService.new

      begin
        # If we don't have a TMDB ID, try to fetch it from IMDB ID
        if @tmdb_id.blank? && @imdb_id.present?
          found = tmdb.find_by_imdb_id(@imdb_id)
          @tmdb_id = found['tv_results']&.first&.dig('id')&.to_s
          Rails.logger.info "Found TMDB ID #{@tmdb_id} for IMDB ID #{@imdb_id}" if @tmdb_id
        end

        if @tmdb_id.present?
          @show_details = tmdb.fetch_show(@tmdb_id)
          @number_of_seasons = @show_details['number_of_seasons']

          @season ||= 1
          @episode ||= 1
          @current_episode = tmdb.fetch_episode(@tmdb_id, @season, @episode)
        end
      rescue TmdbService::RequestError => e
        # The page still plays without episode metadata, so degrade rather than error.
        Rails.logger.error "Error fetching TMDB data: #{e.message}"
        @show_details = nil
        @current_episode = nil
        @season ||= 1
        @episode ||= 1
      end
    end

    # Source resolution for the initial iframe + switcher. No Entry exists here, so we
    # build URLs straight from the active imdb providers (shared by the switcher partial).
    @source_media_key = if @media_type == 'tv'
                          (@season && @episode) ? 'episode' : 'series'
                        else
                          'movie'
                        end
    @source_vars = {
      imdb: @imdb_id, series_imdb: @imdb_id,
      season: @season, episode: @episode, absolute_episode: @episode, source_key: nil
    }
    @default_source = Source.active.where(kind: 'imdb').order(:position).first

    # Set sidebar state for watch_now page
    @sidebar_collapsed = false
    @hide_sidebar = false
    @now_playing_collapsed = true # Collapsed by default on watch_now page
  end
end
