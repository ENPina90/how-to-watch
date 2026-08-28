require 'rails_helper'

# The Add to Channel button on watch_now used to call a global openWatchNowModal, which
# reached for `element.listSearchController` -- not something Stimulus exposes -- and then
# fell through to a document event. It opens the same modal the search results overlay
# does now, through a controller of its own.
RSpec.describe 'Add to Channel on watch_now', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def watch(**params)
    get watch_now_path(imdb: 'tt0062622', title: '2001: A Space Odyssey', type: 'movie',
                       poster: '/poster.png', **params)
  end

  it 'carries the button' do
    watch

    expect(response.body).to include('Add to Channel')
    expect(response.body).to include('data-controller="add-to-list"')
    expect(response.body).to include('data-action="add-to-list#open"')
  end

  it 'hands it what is playing' do
    watch

    expect(response.body).to include('data-add-to-list-imdb-value="tt0062622"')
    expect(response.body).to include('data-add-to-list-poster-value="/poster.png"')
    expect(response.body).to include(%(data-add-to-list-title-value="2001: A Space Odyssey"))
  end

  it 'looks like the one in the search results overlay' do
    watch

    expect(response.body).to include('class="btn btn-primary btn-sm"')
    expect(response.body).to include('<i class="fas fa-plus me-1"></i>Add to Channel')
  end

  # It shares the switcher's line, which means sharing the switcher's containing block:
  # inside .cinema__screen, where --below-frame is defined. Below the frame it would be
  # the only thing under the fold.
  it 'sits inside the frame, alongside the source switcher' do
    watch

    expect(response.body).to include('class="watch-now-add"')
    expect(response.body.index('class="watch-now-add"'))
      .to be > response.body.index('class="cinema__screen"')
    expect(response.body).not_to include('<div class="text-center mt-3">')
  end

  it 'leaves no caller for the global shim, which is gone' do
    watch

    expect(response.body).not_to include('openWatchNowModal')
    expect(response.body).not_to include('onclick=')
  end
end
