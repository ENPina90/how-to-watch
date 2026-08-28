require 'rails_helper'

# The overlay belongs to the search box rather than to its results: focusing the box opens
# it, so the tabs that decide what is being searched can be chosen before anything is typed.
RSpec.describe 'Opening the search overlay', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  it 'opens on focus as well as on input' do
    get list_path(list)

    # Sliced by container, not by tag: a `<input[^>]*>` regex stops at the `>` inside
    # `input->list-search#...` and never reaches the rest of the attributes.
    input = response.body[/<div class="search-container">.*?<\/div>/m]

    expect(input).to include('input->list-search#performSearch')
    expect(input).to include('focus->list-search#openOverlay')
  end

  it 'still ships the tabs, which is what focus is for' do
    get list_path(list)

    expect(response.body).to include('for="navShowType">Series</label>')
    expect(response.body).to include('data-list-search-target="typeButtons"')
  end
end
