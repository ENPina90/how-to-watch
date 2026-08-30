require 'rails_helper'

# The ballot is served in the mobile layout, which is a light page. Written in the app's
# own dark colours, it came out white on near-white -- so it carries its own surface.
RSpec.describe 'The ballot on a phone', :needs_provider, type: :request do
  let(:host) { create(:user) }
  let(:list) { create(:list, user: host, name: 'Friday') }
  let(:phone) do
    { 'HTTP_USER_AGENT' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile/15E148' }
  end

  before do
    %w[Alien Arrival].each_with_index { |n, i| create(:entry, list: list, name: n, imdb: "tt#{i}", position: i + 1) }
    sign_in host
    post list_vote_path(list), params: { count: 2 }
    sign_out host
  end

  it 'is the ballot view, not the room screen' do
    get list_vote_path(list), headers: phone

    expect(response.body).to include('vote-ballot')
    expect(response.body).not_to include('vote-qr')
  end

  it 'paints its own surface rather than inheriting the light one' do
    get list_vote_path(list), headers: phone

    css = Rails.root.join('app/assets/builds/application.css').read
    ballot = css[/\.vote-ballot\{[^}]*\}/]

    expect(ballot).to include('background-color:#0a0a0a')
    expect(ballot).to include('color:#fff')
    expect(ballot).to include('min-height:100vh')
  end

  it 'still offers every option as something to tap' do
    get list_vote_path(list), headers: phone

    expect(response.body.scan('vote-ballot__option').count).to be >= 2
  end
end
