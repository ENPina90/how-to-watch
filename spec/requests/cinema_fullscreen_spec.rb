# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Fullscreen on the player page', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:channel) { create(:list, user: user, auto_next: true) }
  let(:entry) { create(:entry, list: channel, media: 'movie', imdb: 'tt0111161') }

  before { sign_in user }

  # The opening tag of the cinema screen, which is where its controllers are declared.
  def screen_tag
    response.body[/<div class="cinema__screen"[^>]*>/m]
  end

  # The container goes fullscreen, not the frame, so everything the page is for stays on
  # screen instead of vanishing behind a third-party player.
  it 'hangs fullscreen on the cinema screen' do
    get watch_entry_path(entry)

    expect(screen_tag).to match(/data-controller="[^"]*\bcinema-fullscreen\b/)
    expect(response.body).to include('click->cinema-fullscreen#toggle')
  end

  # A second `data-controller` on the same element is not an error anywhere: the parser
  # keeps the first and drops the rest, so the controller simply never connects. That is
  # how the progress controller came to be silently dead for a while.
  it 'declares its controllers in one attribute' do
    get watch_entry_path(entry)

    expect(screen_tag.scan('data-controller=').length).to eq(1)
  end

  # Withholding the permission is what makes that stick: the player's button, its `f` and
  # its double-click all go dead together, and fullscreen taken by the frame cannot be
  # moved back to an ancestor without a fresh gesture we have no way to get.
  it 'does not let the player take the screen for itself' do
    get watch_entry_path(entry)

    frame = response.body[/<iframe id="cinema".*?>/m]
    expect(frame).to be_present
    expect(frame).not_to include('allowfullscreen')
    # Autoplay is a different permission and stays.
    expect(frame).to include('allow="autoplay"')
  end

  # Anything outside the fullscreen element is not rendered at all while fullscreen, and a
  # countdown nobody can see would advance the channel unannounced.
  it 'keeps the up-next card inside the element that goes fullscreen' do
    get watch_entry_path(entry)

    screen = response.body[/<div class="cinema__screen".*<\/div>/m]
    expect(screen).to include('data-controller="auto-advance"')
  end

  it 'offers a way in that does not depend on the player' do
    get watch_entry_path(entry)

    expect(response.body).to include('class="cinema__fullscreen"')
  end
end
