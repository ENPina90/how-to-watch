require 'rails_helper'

# The home page as a signed-out visitor sees it, where the access mode lets one in. It used
# to be the public shelf on a cream page with a stand-by card on every channel and no
# sidebar -- nothing on it that said what any channel held, or what was on.
RSpec.describe 'The home page signed out', :needs_provider, type: :request do
  let(:owner) { create(:user) }
  let!(:westerns) { create(:list, user: owner, name: 'Westerns') }
  let!(:shane) { create(:entry, list: westerns, name: 'Shane', pic: 'https://example.com/shane.jpg', position: 1) }

  before { AppSetting.update_access_mode!('moderate') }

  def sidebar
    response.body[%r{<div id="sidebarChannels".*?</div>\s*</div>}m]
  end

  it 'renders dark' do
    get lists_path

    expect(response.body).to match(/<body class="[^"]*\bdark-mode\b/)
  end

  describe 'the cards' do
    it 'shows a picture from the channel instead of standing by' do
      get lists_path

      expect(response.body).to include('https://example.com/shane.jpg')
      expect(response.body).not_to match(%r{please_stand_by\.png" alt="Westerns"})
    end

    it 'opens the channel where the visitor cannot play it' do
      get lists_path

      expect(response.body).to include(%(href="#{list_path(westerns)}"))
      expect(response.body).not_to include(list_watch_current_path(westerns))
    end

    it 'plays the channel where the visitor can' do
      AppSetting.update_access_mode!('open')

      get lists_path

      expect(response.body).to include(list_watch_current_path(westerns))
    end

    it 'still stands by for a channel with no pictures in it' do
      shane.update!(pic: '')

      get lists_path

      expect(response.body).to match(%r{please_stand_by\.png" alt="Westerns"})
    end

    it 'borrows a picture from the channels inside one' do
      hub = create(:list, user: owner, name: 'Frontier')
      westerns.add_to_parent(hub)

      get lists_path

      expect(response.body).not_to match(%r{please_stand_by\.png" alt="Frontier"})
    end

    it 'does not show a private channel through the public one holding it' do
      hub = create(:list, user: owner, name: 'Frontier')
      hidden = create(:list, user: owner, name: 'Hidden', private: true)
      create(:entry, list: hidden, name: 'Solaris', pic: 'https://example.com/solaris.jpg', position: 1)
      hidden.add_to_parent(hub)

      get lists_path

      expect(response.body).not_to include('https://example.com/solaris.jpg')
    end

    it 'costs no more queries for more channels than a member’s page does' do
      build = lambda do |count|
        count.times do |i|
          list = create(:list, user: owner, name: "Channel #{count}-#{i}")
          create(:entry, list: list, position: 1, name: "Entry #{count}-#{i}")
        end
      end

      queries = lambda do
        get lists_path
        count = 0
        subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
          count += 1 unless payload[:name].to_s =~ /SCHEMA|TRANSACTION/
        end
        get lists_path
        ActiveSupport::Notifications.unsubscribe(subscriber)
        count
      end

      build.call(3)
      few = queries.call
      build.call(12)
      many = queries.call

      expect(many - few).to be <= 2
    end
  end

  describe 'the sidebar' do
    let!(:on_the_dial) { create(:list, user: owner, name: 'Channel One', default: true, cable_position: 1) }

    it 'lists the dial rather than subscriptions' do
      get lists_path

      expect(sidebar).to include('Channel One')
      expect(sidebar).not_to include('Westerns')
      expect(response.body).not_to include('Your Subscriptions')
    end

    it 'leaves a private channel off it' do
      on_the_dial.update!(private: true)

      get lists_path

      expect(sidebar).not_to include('Channel One')
    end

    it 'shows what is playing' do
      get lists_path

      expect(response.body).to include('Now Playing')
    end

    it 'stays off the sign-in page' do
      get new_user_session_path

      expect(response.body).not_to include('id="mainSidebar"')
    end
  end
end
