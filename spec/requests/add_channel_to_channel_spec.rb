require 'rails_helper'

# The Channels tab of the search overlay files one channel inside another, the same way the
# + on an entry files an entry: into the channel behind the overlay, or into whichever the
# picker is answered with. It posts to the endpoint the channel page's own "Add to another
# channel" menu uses, so the rules about cycles and ownership are stated once.
RSpec.describe 'Adding a channel to a channel', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:parent) { create(:list, user: user, name: 'Nights In') }
  let(:child) { create(:list, user: user, name: 'Noir') }

  before do
    sign_in user
    create(:entry, list: parent, position: 1)
  end

  it 'offers the button on a channel result' do
    get list_path(parent)

    template = response.body[/<template id="listSearchListTemplate">.*?<\/template>/m]

    expect(template).to include('data-kind="channel"')
    expect(template).to include('click->list-search#add')
    expect(template).to include('data-list-id="{{id}}"')
  end

  # A child channel belongs to no section, so a grouped view had nowhere to put it and
  # dropped it -- adding one looked like nothing had happened.
  it 'shows a child channel in a grouped view as well as in order' do
    child.add_to_parent(parent)

    get list_path(parent, criteria: 'Year')

    expect(response.body).to include('child-channels')
    expect(response.body).to include(child.name)
  end

  it 'files it, and streams its card onto the page that asked' do
    patch list_move_to_list_path(child, target_list_id: parent.id), as: :turbo_stream

    expect(parent.child_lists).to include(child)
    expect(response.body).to include('target="list-entries"')
    expect(response.body).to include('Noir')
  end

  it 'still redirects the page that posts a form' do
    patch list_move_to_list_path(child, target_list_id: parent.id)

    expect(response).to redirect_to(list_path(parent))
    expect(parent.child_lists).to include(child)
  end

  # The overlay reports a refusal on the button it was clicked from, which needs a status
  # rather than a redirect carrying a flash.
  it 'refuses a cycle with an error status' do
    child.add_to_parent(parent)

    patch list_move_to_list_path(parent, target_list_id: child.id), as: :turbo_stream

    expect(response).to have_http_status(:unprocessable_entity)
    expect(child.child_lists).not_to include(parent)
  end

  it 'refuses a channel that is not yours to add to' do
    stranger = create(:list, user: create(:user), name: 'Theirs')

    patch list_move_to_list_path(child, target_list_id: stranger.id), as: :turbo_stream

    expect(response).to have_http_status(:forbidden)
    expect(stranger.child_lists).not_to include(child)
  end

  # The overlay renders whatever comes back, refusal included, so the reason has to be in
  # the response rather than only in a redirect the fetch would never follow. And it has to
  # be the actual reason: one message covering all three read as a cycle even when the
  # channel was simply already there.
  describe 'the reason it gives' do
    it 'says a channel is already there, rather than blaming a cycle' do
      child.add_to_parent(parent)

      patch list_move_to_list_path(child, target_list_id: parent.id), as: :turbo_stream

      expect(response.body).to include('<turbo-stream')
      expect(response.body).to include("#{child.name} is already in #{parent.name}")
      expect(response.body).not_to include('circular')
    end

    it 'names the loop when there would actually be one' do
      child.add_to_parent(parent)

      patch list_move_to_list_path(parent, target_list_id: child.id), as: :turbo_stream

      expect(response.body).to include("#{child.name} is already inside #{parent.name}")
    end

    it 'says so when a channel is added to itself' do
      patch list_move_to_list_path(parent, target_list_id: parent.id), as: :turbo_stream

      expect(response.body).to include('cannot be added to itself')
    end
  end

  it 'refuses adding one twice' do
    child.add_to_parent(parent)

    patch list_move_to_list_path(child, target_list_id: parent.id), as: :turbo_stream

    expect(response).to have_http_status(:unprocessable_entity)
    expect(parent.child_lists.where(id: child.id).count).to eq(1)
  end
end
