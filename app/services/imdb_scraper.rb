require 'nokogiri'
require 'httparty'

class ImdbScraper

  def initialize(list, imdb_id)
    @imdb_id = imdb_id
    @list = list
    @url = "https://www.imdb.com/search/title/?user_rating=7,#{lowest_rating}&count=250&series=#{@imdb_id}&sort=user_rating,desc"
  end


  def fetch_episode_imdb_ids_with_ratings
    # Set headers to mimic a real browser
    headers = {
      "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
      "Accept-Language" => "en-US,en;q=0.9",
      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8",
      "Connection" => "keep-alive"
    }

    # Fetch the HTML content of the page
    response = HTTParty.get(@url, headers: headers)

    if response.success?
      # Parse the page with Nokogiri
      page = Nokogiri::HTML(response.body)

      # Find all elements with class "ipc-metadata-list-summary-item"
      episode_elements = page.css('.ipc-metadata-list-summary-item')

      # Extract the IMDb ID, episode title, and rating
      episodes = episode_elements.map do |element|
        # Extract IMDb ID from the 'ep-title'
        href = element.css('.ep-title a').first['href']
        imdb_id = href.match(/\/title\/(tt\d+)\//)[1]

        # Extract the title
        title = element.css('.ep-title h3').text.strip

        # Extract the rating (if present)
        rating_element = element.css('.ipc-rating-star--rating').first
        rating = rating_element ? rating_element.text.strip.to_f : nil

        { imdb_id: imdb_id, title: title, rating: rating }
      end

      filter_episodes(episodes)
    else
      puts "Failed to fetch the page: #{@url}"
      []
    end
  end

  private

  def filter_episodes(episodes)
    # Filter out episodes that are already in the list
    existing_ids = @list.entries.map(&:imdb)
    episodes.reject { |episode| existing_ids.include?(episode[:imdb_id]) }
  end

  def lowest_rating
    # I'm using this to so that every time I fetch the top episodes it starts with the lowest rated ep in our list as the upper limit, so that it's 25 new entries every time
    ratings = @list.entries.where(series_imdb: @imdb_id).map(&:rating).sort
    ratings = ratings.reject{|n| n == 0.0 }
    ratings.sort.first || 10
  end
end
