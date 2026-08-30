require 'rails_helper'

# Playing a channel from another channel's page. This is the path "Pick for me" and a
# channel row's play button both take, and it used to hand you to the channel that owns the
# entry -- or, for a channel holding nothing of its own, refuse outright.
RSpec.describe 'Playing a channel from the page you are on', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:hub) { create(:list, user: user, name: 'List of Lists') }
  let(:child) { create(:list, user: user, name: 'School Night In') }
  let!(:borrowed) { create(:entry, list: child, name: 'Arrival', imdb: 'tt2', position: 1) }

  before do
    sign_in user
    child.add_to_parent(hub)
  end

  it 'plays a channel that holds nothing of its own' do
    expect(hub.entries).to be_empty

    get list_watch_current_path(hub)

    expect(response).to redirect_to(watch_entry_path(borrowed, channel: hub.id))
  end

  it 'stays on the page the channel row was clicked from' do
    get list_watch_current_path(child, channel: hub.id)

    expect(response).to redirect_to(watch_entry_path(borrowed, channel: hub.id))
  end

  it 'plays the channel on its own page as itself' do
    get list_watch_current_path(child)

    expect(response).to redirect_to(watch_entry_path(borrowed, channel: child.id))
  end

  it 'sends the page along on the row’s play button' do
    get list_path(hub, criteria: 'Position')

    expect(response.body).to include(list_watch_current_path(child, channel: hub.id))
  end

  it 'still reports a channel with nothing anywhere under it' do
    empty = create(:list, user: user, name: 'Nothing Yet')

    get list_watch_current_path(empty)

    expect(response).to redirect_to(list_path(empty))
    expect(flash[:notice]).to include('no entries to watch')
  end

  # Position is a number within the channel that owns the entry.
  it 'does not record a borrowed entry as the borrowing channel’s position' do
    get list_watch_current_path(hub)

    expect(hub.position_for_user(user)).to be_nil
  end

  it 'prefers the channel’s own entry over one it borrows' do
    hub.update!(ordered: true)
    own = create(:entry, list: hub, name: 'Alien', imdb: 'tt1', position: 1)

    get list_watch_current_path(hub)

    expect(response).to redirect_to(watch_entry_path(own, channel: hub.id))
  end
end
