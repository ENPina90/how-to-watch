# frozen_string_literal: true

require 'rails_helper'

# The Community Channels row on the home page is for finding channels. It used to be public
# channels plus the ones the member already subscribed to, newest first -- so the dial and
# the sidebar's own contents took up the row, and a channel people were watching every day
# sank below one made yesterday and never touched.
RSpec.describe 'The Community Channels row', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:owner) { create(:user) }

  before { sign_in user }

  # Read off the row itself: the sidebar carries channel names too.
  def community_row
    row = Nokogiri::HTML(response.body).css('.list-row')
                  .find { |node| node.at('.row-title')&.text&.strip == 'Community Channels' }
    row ? row.css('.list-card-name').map { |name| name.text.strip } : []
  end

  def channel(name, **attrs)
    create(:list, user: owner, name: name, **attrs).tap do |list|
      create(:entry, list: list, name: "#{name} entry", position: 1)
    end
  end

  # Every write above stamps now; spread them out so the order is the one under test.
  def active_at(list, time)
    list.update_columns(created_at: time, updated_at: time)
    list.entries.update_all(created_at: time, updated_at: time)
  end

  it 'shows a public channel the member has not found' do
    channel('Westerns')

    get lists_path

    expect(community_row).to include('Westerns')
  end

  it 'leaves out channels the member subscribes to' do
    westerns = channel('Westerns')
    Subscription.create!(user: user, list: westerns)

    get lists_path

    expect(community_row).not_to include('Westerns')
  end

  it 'leaves out the cable dial even once the member has unsubscribed from it' do
    dial = channel('Channel One', default: true, cable_position: 1)
    Subscription.where(user: user, list: dial).destroy_all

    get lists_path

    expect(community_row).not_to include('Channel One')
  end

  it 'leaves out the member’s own channels' do
    create(:list, user: user, name: 'Mine')

    get lists_path

    expect(community_row).not_to include('Mine')
  end

  it 'leaves out private channels' do
    channel('Hidden', private: true)

    get lists_path

    expect(community_row).not_to include('Hidden')
  end

  it 'still shows an admin private channels' do
    user.update!(admin: true)
    channel('Hidden', private: true)

    get lists_path

    expect(community_row).to include('Hidden')
  end

  describe 'the order' do
    let!(:old_channel) { channel('Old Channel') }
    let!(:newer_channel) { channel('Newer Channel') }

    before do
      active_at(old_channel, 1.year.ago)
      active_at(newer_channel, 1.week.ago)
    end

    it 'puts the channel something happened on most recently first' do
      get lists_path

      expect(community_row).to eq(['Newer Channel', 'Old Channel'])
    end

    it 'counts somebody watching as activity' do
      old_channel.entries.first.mark_completed_by!(create(:user))

      get lists_path

      expect(community_row).to eq(['Old Channel', 'Newer Channel'])
    end

    it 'counts somebody moving their place as activity' do
      UserListPosition.create!(user: create(:user), list: old_channel, current_position: 1)

      get lists_path

      expect(community_row).to eq(['Old Channel', 'Newer Channel'])
    end

    it 'counts an entry being added as activity' do
      create(:entry, list: old_channel, name: 'Fresh', position: 2)

      get lists_path

      expect(community_row).to eq(['Old Channel', 'Newer Channel'])
    end
  end

  describe 'signed out' do
    before do
      sign_out user
      AppSetting.update_access_mode!('moderate')
    end

    it 'leaves out the cable dial' do
      channel('Westerns')
      channel('Channel One', default: true, cable_position: 1)

      get lists_path

      expect(community_row).to include('Westerns')
      expect(community_row).not_to include('Channel One')
    end
  end
end
