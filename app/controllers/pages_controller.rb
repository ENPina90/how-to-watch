require 'open-uri'
require 'json'

class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home ]

  def home
  end

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
      begin
        tmdb_api_key = TmdbService.api_key

        # If we don't have a TMDB ID, try to fetch it from IMDB ID
        if !@tmdb_id.present? && @imdb_id.present?
          find_url = "https://api.themoviedb.org/3/find/#{@imdb_id}?api_key=#{tmdb_api_key}&external_source=imdb_id"
          find_response = URI.open(find_url).read
          find_data = JSON.parse(find_response)

          if find_data['tv_results'] && find_data['tv_results'].length > 0
            @tmdb_id = find_data['tv_results'][0]['id'].to_s
            Rails.logger.info "Found TMDB ID #{@tmdb_id} for IMDB ID #{@imdb_id}"
          end
        end

        # Continue only if we have a TMDB ID
        if @tmdb_id.present?
          # Fetch show details to get number of seasons
          show_url = "https://api.themoviedb.org/3/tv/#{@tmdb_id}?api_key=#{tmdb_api_key}"
          show_response = URI.open(show_url).read
          @show_details = JSON.parse(show_response)
          @number_of_seasons = @show_details['number_of_seasons']

          # Set default season and episode if not provided
          @season ||= 1
          @episode ||= 1

          # Fetch current episode details
          episode_url = "https://api.themoviedb.org/3/tv/#{@tmdb_id}/season/#{@season}/episode/#{@episode}?api_key=#{tmdb_api_key}"
          episode_response = URI.open(episode_url).read
          @current_episode = JSON.parse(episode_response)
        end
      rescue => e
        Rails.logger.error "Error fetching TMDB data: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        @show_details = nil
        @current_episode = nil
        # Set defaults if API fails
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
