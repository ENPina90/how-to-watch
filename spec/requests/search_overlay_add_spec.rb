require 'rails_helper'

# The overlay does what /entries/new does: its buttons name what they add ("+ Movie",
# "+ Show", "+ Episode", "+ Season") rather than where it goes, and where it goes depends
# on where the search was made from -- the channel you are on takes it outright, anywhere
# else is asked which channel.
RSpec.describe 'Adding from the search overlay', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Noir') }

  before do
    sign_in user
    create(:entry, list: list, name: 'Alien', position: 1)
  end

  describe 'which channel a result goes to' do
    it 'names the channel being viewed, so the button can add to it outright' do
      get list_path(list)

      expect(response.body).to include(%(data-list-search-current-list-id-value="#{list.id}"))
    end

    it 'leaves it blank off a channel page, where the picker has to ask' do
      get lists_path

      expect(response.body).to include('data-list-search-current-list-id-value=""')
    end
  end

  # The templates render client-side, so the page ships the markup and the controller
  # fills in the label for the tab you are on.
  describe 'the result templates' do
    before { get list_path(list) }

    it 'labels the add button by media type rather than destination' do
      expect(response.body.scan('{{addLabel}}').count).to eq(2)

      # A movie or series names what it is. The one button that still names a channel is
      # on a channel result, where the channel *is* what is being added.
      %w[listSearchMovieTemplate listSearchShowTemplate].each do |template|
        markup = response.body[/<template id="#{template}">.*?<\/template>/m]

        expect(markup).not_to include('</i>Add to Channel')
      end
    end

    # Movie, series, episode, season -- and a channel filed inside another channel.
    it 'routes every add through one action' do
      expect(response.body.scan('click->list-search#add"').count).to eq(5)
    end

    it 'offers a show its episodes' do
      expect(response.body).to include('click->list-search#seeEpisodes')
      expect(response.body).to include('See Episodes')
    end

    # Everything the episodes view needs is on the result already, so opening it costs no
    # round trip to TMDB for the show itself.
    it 'hands See Episodes the season count and the series id off the card' do
      episodes = response.body[/<button(?:(?!<\/button>).)*seeEpisodes(?:(?!<\/button>).)*<\/button>/m]

      expect(episodes).to include('data-seasons="{{totalSeasons}}"')
      expect(episodes).to include('data-imdb-id="{{imdbID}}"')
      expect(episodes).to include('data-tmdb-id="{{tmdbID}}"')
    end

    it 'carries an episodes view with a season picker and both buttons' do
      expect(response.body).to include('id="listSearchEpisodeTemplate"')
      expect(response.body).to include('change->list-search#changeSeason')
      expect(response.body).to include('click->list-search#backToResults')
      expect(response.body).to include('data-kind="season"')
    end

    it 'gives an episode the season and number the entries endpoint needs' do
      episode = response.body[/data-action="click->list-search#add"(?:(?!<\/button>).)*data-episode="\{\{Episode\}\}"/m]

      expect(episode).to be_present
      expect(episode).to include('data-series-imdb-id="{{seriesImdbID}}"')
      expect(episode).to include('data-season="{{Season}}"')
    end
  end

  # Both endpoints already existed for the /entries/new forms; the overlay posts to them
  # rather than growing its own.
  describe 'the endpoints behind the buttons' do
    def recognize(path)
      Rails.application.routes.recognize_path(path, method: :post)
    end

    it 'posts an entry to the channel in the path' do
      expect(recognize("/lists/#{list.id}/entries"))
        .to include(controller: 'entries', action: 'create', list_id: list.id.to_s)
    end

    it 'posts a season import to the channel in the path' do
      expect(recognize("/lists/#{list.id}/add_season"))
        .to include(controller: 'lists', action: 'add_season', list_id: list.id.to_s)
    end
  end
end
