require 'rails_helper'

# The playback readout on the watch page, reached with ?debug=1.
#
# It is an instrument, so the things worth pinning are that it is absent unless asked for,
# and that it is rendered somewhere a move between entries and a spell in fullscreen both
# leave alone -- a readout replaced halfway through the evening records half an evening,
# and one outside the fullscreen element records the two hours nobody can see it.
RSpec.describe 'The playback readout', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list, name: 'Stalker', imdb: 'tt1', media: 'movie', position: 1) }

  before { sign_in user }

  it 'is absent from an ordinary watch page' do
    get watch_entry_path(entry)

    expect(response.body).not_to include('playback-debug')
  end

  it 'appears when it is asked for' do
    get watch_entry_path(entry, debug: '1')

    expect(response.body).to include('data-controller="playback-debug"')
  end

  it 'says which adapter, if any, can drive the player' do
    get watch_entry_path(entry, debug: '1')

    expect(response.body).to include(%(data-adapter="#{playable_provider.sync_adapter}"))
  end

  # The chrome is replaced wholesale by every move between entries, so a readout inside it
  # would start again each time -- and the run either side of a move is exactly what a
  # channel-surfing fault looks like.
  it 'sits outside the chrome, which a move replaces' do
    get watch_entry_path(entry, debug: '1')

    chrome = response.body[/<div id="cinema-chrome".*\z/m]

    expect(chrome).not_to include('playback-debug')
  end

  # Fullscreen is granted to the cinema screen, and nothing outside that element is
  # rendered while it is held -- which is most of the time a film is being watched.
  it 'sits inside the element that goes fullscreen' do
    get watch_entry_path(entry, debug: '1')

    screen = response.body[/<div class="cinema__screen".*\z/m]

    expect(screen).to include('playback-debug')
  end

  # Anything else would be a debugging tool that writes.
  it 'records nothing of its own' do
    expect { get watch_entry_path(entry, debug: '1') }.not_to change(UserEntry, :count)
  end
end
