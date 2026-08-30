require 'rails_helper'

# The sidebar lists what this user is subscribed to, which is exactly what the subscribe
# button changes -- and it used to sit there unchanged until the next page load.
RSpec.describe 'Subscriptions in the sidebar', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:mine) { create(:list, user: user, name: 'Noir') }
  let(:theirs) { create(:list, user: create(:user), name: 'Westerns') }

  before { sign_in user }

  it 'calls the sidebar what it holds' do
    get lists_path

    expect(response.body).to include('Your Subscriptions')
    expect(response.body).not_to include('Your Library')
  end

  it 'lists a channel once subscribed to it' do
    user.subscribe_to!(theirs)

    get lists_path

    sidebar = response.body[/<div id="sidebarChannels".*?<\/div>\s*<\/div>/m]
    expect(sidebar).to include('Westerns')
  end

  # A new account is subscribed to its own Favorites channel, so this takes unsubscribing
  # from everything to reach.
  it 'says so when there is nothing subscribed' do
    user.subscribed_lists.to_a.each { |list| user.unsubscribe_from!(list) }

    get lists_path

    expect(response.body).to include('Nothing subscribed yet.')
  end

  describe 'subscribing' do
    it 'streams the sidebar back with the channel in it' do
      patch list_subscribe_path(theirs), as: :turbo_stream

      expect(response.body).to include('target="sidebarChannels"')
      expect(response.body).to include('Westerns')
    end

    # The message belongs to the click that caused it. Set for the next request instead,
    # it said nothing at the time and then turned up on whatever page was opened next.
    it 'says so in the same response, and leaves nothing behind for the next one' do
      patch list_subscribe_path(theirs), as: :turbo_stream

      expect(response.body).to include('target="flash"')
      expect(response.body).to include("Subscribed to #{theirs.name}")

      # flash.now, so it is spent here rather than waiting for the next page.
      get lists_path
      expect(response.body).not_to include("Subscribed to #{theirs.name}")
    end

    it 'streams the button back too' do
      patch list_subscribe_path(theirs), as: :turbo_stream

      expect(response.body).to include(%(target="subscription-#{theirs.id}"))
      expect(response.body).to include('Subscribed')
    end
  end

  describe 'unsubscribing' do
    before { user.subscribe_to!(theirs) }

    it 'says so in the same response' do
      patch list_unsubscribe_path(theirs), as: :turbo_stream

      expect(response.body).to include("Unsubscribed from #{theirs.name}")

      get lists_path
      expect(response.body).not_to include("Unsubscribed from #{theirs.name}")
    end

    it 'still carries the message on a plain form post, which goes somewhere else' do
      patch list_unsubscribe_path(theirs)

      expect(response).to redirect_to(list_path(theirs))
      expect(flash[:notice]).to eq("Unsubscribed from #{theirs.name}")
    end

    it 'streams the sidebar back without it' do
      patch list_unsubscribe_path(theirs), as: :turbo_stream

      sidebar = response.body[/<turbo-stream[^>]*target="sidebarChannels".*?<\/turbo-stream>/m]

      expect(sidebar).to be_present
      expect(sidebar).not_to include('Westerns')
    end
  end
end
