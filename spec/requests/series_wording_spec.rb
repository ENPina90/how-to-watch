require 'rails_helper'

# The media type reads as Series everywhere a person sees it. The word `show` is still the
# search type in the params, the template ids, the controller methods and TMDB's own API,
# so the rename stops at the copy.
RSpec.describe 'Series wording', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  it 'names the search tab Series' do
    get list_path(list)

    expect(response.body).to include('for="navShowType">Series</label>')
    expect(response.body).not_to include('>Shows</label>')
  end

  it 'says so in the search box too' do
    get list_path(list)

    expect(response.body).to include('placeholder="Search movies & series..."')
    expect(response.body).to include('aria-label="Search movies and series"')
  end

  it 'labels the add button and the type menu on /entries/new' do
    get new_list_entry_path(list, type: 'show')

    expect(response.body).to include('>Series</a>')
    expect(response.body).to include('+ Series')
    expect(response.body).not_to include('>Show</a>')
  end

  # Labels, not values: the media column and the type param still say show.
  it 'leaves the wiring alone' do
    get new_list_entry_path(list, type: 'show')

    expect(response.body).to include(new_list_entry_path(list, type: 'show'))
    expect(response.body).to include('id="listSearchShowTemplate"')
    expect(response.body).to include('list-search#switchToShowSearch')
  end

  it 'offers Series as a media label over the value the column stores' do
    get new_list_entry_path(list)

    media = response.body[/<select[^>]*entry_media.*?<\/select>/m]

    expect(media).to include('<option value="show">Series</option>')
  end
end
