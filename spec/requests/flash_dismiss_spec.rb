require 'rails_helper'

# A flash says what just happened. It used to stay until it was clicked, which on a page
# you keep working in means a stack of things that already happened.
RSpec.describe 'Flashes going away on their own', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Noir') }
  # Someone else's: an account is auto-subscribed to its own channels, so subscribing to
  # one of those is the "already subscribed" path rather than a notice.
  let(:theirs) { create(:list, user: create(:user), name: 'Westerns') }

  before { sign_in user }

  it 'wires a notice to close itself' do
    patch list_subscribe_path(theirs)
    follow_redirect!

    expect(response.body).to include('alert-info')
    expect(response.body).to include('data-controller="dismiss"')
  end

  it 'wires an alert the same way' do
    stranger = create(:list, user: create(:user))

    patch list_move_to_list_path(list, target_list_id: stranger.id)
    follow_redirect!

    expect(response.body).to include('alert-warning')
    expect(response.body).to include('data-controller="dismiss"')
  end

  # A flash arriving by stream is a new element, so it gets its own timer rather than
  # inheriting one that has already run out.
  it 'wires one that arrives in a stream too' do
    entry = create(:entry, list: list, position: 1)

    delete entry_path(entry), as: :turbo_stream

    expect(response.body).to include('target="flash"')
    expect(response.body).to include('data-controller="dismiss"')
  end

  it 'keeps the close button, for anyone who would rather not wait' do
    patch list_subscribe_path(theirs)
    follow_redirect!

    expect(response.body).to include('data-bs-dismiss="alert"')
  end
end
