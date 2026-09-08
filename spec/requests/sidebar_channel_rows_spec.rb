# frozen_string_literal: true

require 'rails_helper'

# The two sidebars on the player page: the channels down the left, the entries down the
# right. They had drifted apart -- different marks for "this is the one you are on", and a
# channel row that went somewhere different depending on which page you clicked it from.
RSpec.describe 'Player sidebars', :needs_provider do
  let(:user) { create(:user) }
  let(:channel) { create(:list, user: user, name: 'Best of Stargate') }
  let(:other) { create(:list, user: user, name: 'Adult Swim Happy Hour') }
  let!(:entry) { create(:entry, list: channel, name: 'Children of the Gods') }

  before do
    # Creating a channel already subscribes its owner to it.
    Subscription.find_or_create_by!(user: user, list: channel)
    Subscription.find_or_create_by!(user: user, list: other)
    sign_in user
  end

  describe 'a channel row' do
    it 'plays the channel when the row itself is clicked' do
      get watch_entry_path(entry)

      expect(response.body).to include(list_watch_current_path(other))
    end

    # It used to open the channel page from a list page and play from a player page, so the
    # same row did two different things depending on where you found it.
    it 'plays the channel from a channel page too, not just from a player' do
      get list_path(channel)

      expect(response.body).to include(list_watch_current_path(other))
    end

    it 'offers the channel page on its own control rather than on the whole row' do
      get watch_entry_path(entry)

      expect(response.body).to include('sidebar-channel__open')
      expect(response.body).to include(list_path(other))
    end

    it 'no longer carries an icon in front of every name' do
      get watch_entry_path(entry)

      # The row itself, not the whole block: the icon that is left lives in the sibling
      # link beside it, and matching across rows would find that one.
      row_links = response.body.scan(%r{<a class="list-group-item.*?</a>}m)
      expect(row_links).to be_present
      expect(row_links.join).not_to include('fa-list')
    end
  end

  describe 'marking where you are' do
    # The entries sidebar marks its current row with a background and a weight. The channel
    # list used to add a green rule down the left, which also shifted the row out of line.
    it 'marks the channel being watched the way the entry sidebar marks its entry' do
      get watch_entry_path(entry)

      expect(response.body).to include('active-list')
      expect(response.body).to include('entry-item active')
    end

    it 'points the autoscroll at the current channel and the current entry' do
      get watch_entry_path(entry)

      expect(response.body.scan('sidebar-autoscroll-target="active"').size).to eq(2)
    end

    it 'mounts the autoscroll on both scrolling panels' do
      get watch_entry_path(entry)

      expect(response.body.scan('data-controller="sidebar-autoscroll"').size).to eq(2)
    end
  end
end
