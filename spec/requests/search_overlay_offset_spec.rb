require 'rails_helper'

# The navbar's search results open over the page, and on a channel page that meant over the
# channel's own name. They drop below the sticky header there -- and only there, which is
# what the page class on <body> is for.
RSpec.describe 'The search results overlay', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Noir') }

  before do
    sign_in user
    create(:entry, list: list, name: 'Alien', position: 1)
  end

  it 'marks the channel page so the offset can be scoped to it' do
    get list_path(list)

    expect(response.body).to include('class="page-lists-show')
  end

  it 'does not mark the index, where the overlay covers nothing' do
    get lists_path

    expect(response.body).to include('class="page-lists-index')
    expect(response.body).not_to include('page-lists-show')
  end

  # The geometry has to be in the stylesheet for a page to be able to override it; an
  # inline style would win over both.
  it 'carries no inline position on the overlay itself' do
    get list_path(list)

    overlay = response.body[/<div[^>]*search-results-overlay[^>]*>/]
    expect(overlay).to be_present
    expect(overlay).not_to include('style=')
  end
end
