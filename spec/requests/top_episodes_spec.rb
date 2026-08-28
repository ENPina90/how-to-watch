require 'rails_helper'

# The Top Entries prompt from /entries/new, brought into the overlay -- but showing the
# episodes first. /lists/:id/top_entries scrapes IMDB and redirects, so it can add a show's
# best episodes but never show you which ones; the overlay ranks the seasons it can already
# fetch, so what you see is what gets added, one card at a time through the same endpoint
# as a single episode.
RSpec.describe 'Top rated episodes', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before do
    sign_in user
    create(:entry, list: list, position: 1)
    get list_path(list)
  end

  it 'offers it on a show result, beside See Episodes' do
    show = response.body[/<template id="listSearchShowTemplate">.*?<\/template>/m]

    expect(show).to include('click->list-search#seeEpisodes')
    expect(show).to include('click->list-search#topEpisodes')
    expect(show).to include('Top Rated Episodes')
  end

  it 'offers it in the episodes view, ahead of the season picker' do
    episodes = response.body[/<template id="listSearchEpisodeTemplate">.*?<\/template>/m]

    expect(episodes.index('click->list-search#topEpisodes')).to be < episodes.index('season-picker')
  end

  # One header serving both views: the season controls or the top-rated ones, never both.
  it 'swaps the season controls for the bulk add in the top view' do
    episodes = response.body[/<template id="listSearchEpisodeTemplate">.*?<\/template>/m]

    expect(episodes).to include('{{^top}}')
    expect(episodes).to include('{{#top}}')
    expect(episodes).to include('click->list-search#openTopModal')
    expect(episodes).to include('click->list-search#bySeason')
  end

  it 'asks how many with the same prompt /entries/new uses' do
    expect(response.body).to include('id="topEpisodesModal"')
    expect(response.body).to include('id="topEpisodesSlider"')
    expect(response.body).to include('Select number of episodes to add:')
    expect(response.body).to match(/min="1" max="20" value="10"/)
  end

  it 'keeps the per-episode add, so one can be taken without the batch' do
    episodes = response.body[/<template id="listSearchEpisodeTemplate">.*?<\/template>/m]

    expect(episodes).to include('data-episode="{{Episode}}"')
    expect(episodes).to include('click->list-search#add"')
  end
end
