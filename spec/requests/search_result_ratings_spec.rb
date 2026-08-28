require 'rails_helper'

# The rating comes from the search payload TMDB already returned -- an IMDB rating would
# cost an OMDB request per result. A result with no votes has no rating, and the card drops
# the line rather than printing "N/A/10" or "0/10".
RSpec.describe 'Ratings on search results', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before do
    sign_in user
    create(:entry, list: list, position: 1)
    get list_path(list)
  end

  it 'shows one on a movie and a show, guarded on there being one' do
    expect(response.body.scan('{{Year}}{{#Rating}} • {{.}}/10{{/Rating}}').count).to eq(2)
  end

  it 'shows one on an episode, next to its place in the run' do
    expect(response.body).to include('S{{Season}}E{{Episode}}{{#Rating}} • {{.}}/10{{/Rating}}')
  end

  it 'never prints a bare /10 with nothing in front of it' do
    expect(response.body).not_to include('{{Rating}}/10')
  end
end
