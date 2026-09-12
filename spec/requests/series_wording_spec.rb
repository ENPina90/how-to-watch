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

    expect(response.body).to include('placeholder="Search movies, series, and channels"')
    expect(response.body).to include('aria-label="Search movies, series, and channels"')
  end

  # The overlay's + button is labelled in JavaScript rather than in the template -- the
  # mustache render fills {{addLabel}} in -- so the wording is pinned where it is written.
  # The /entries/new page used to carry a second copy of this label; it has no search on it
  # any more.
  it 'names the overlay\'s add button Series' do
    labels = Rails.root.join('app/javascript/controllers/list_search_controller.js').read

    expect(labels).to include("show: 'Series'")
    expect(labels).not_to include("show: 'Show'")
  end

  # Labels, not values: the type param, the template ids and the controller methods still
  # say show.
  it 'leaves the wiring alone' do
    get list_path(list)

    expect(response.body).to include('id="listSearchShowTemplate"')
    expect(response.body).to include('list-search#switchToShowSearch')
  end

  # `show` was the label's value here too, and it is not a media type the app can draw:
  # `entries/entry_show` is not a partial. The column stores `series`.
  it 'offers Series as a media option the card renderer understands' do
    get new_list_entry_path(list)

    media = response.body[/<select[^>]*entry_media.*?<\/select>/m]

    expect(media).to include('<option value="series">Series</option>')
    expect(media).not_to include('value="show"')
  end
end
