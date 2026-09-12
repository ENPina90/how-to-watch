# frozen_string_literal: true

require 'rails_helper'

# /admin/cable: the dial's settings page.
#
# The guide over a playing channel had room for one admin button, so dealing the schedule
# again was the only thing an admin could do to the dial and everything else -- which
# channels were on it, what order they sat in -- was a console job. This is the page those
# moved to.
RSpec.describe 'The cable settings page', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }

  let!(:provider) do
    Source.create!(
      name: 'Primary', kind: 'imdb', active: true, position: 1,
      templates: { 'movie' => 'https://p.test/movie?imdb=%{imdb}' }
    )
  end

  # Two channels on the dial and one public channel off it, which is the smallest set that
  # can say anything about order, removal and addition all three.
  let!(:one) { create(:list, user: admin, provider: provider, name: 'Channel One', default: true, cable_position: 1) }
  let!(:two) { create(:list, user: admin, provider: provider, name: 'Channel Two', default: true, cable_position: 2) }
  let!(:candidate) { create(:list, user: admin, provider: provider, name: 'Waiting Room', private: false) }

  def stock(list, name)
    create(:entry, list: list, name: name, media: 'movie', length: 90, position: 1,
                   imdb: "tt#{list.id.to_s.rjust(7, '0')}")
  end

  before do
    stock(one, 'The Death of Harvey')
    stock(two, 'A Second Film')
    stock(candidate, 'Not On Yet')
  end

  describe 'who can reach it' do
    it 'opens for an admin' do
      sign_in admin

      get admin_cable_path

      expect(response).to be_successful
      expect(response.body).to include('Channel One')
      expect(response.body).to include('Channel Two')
    end

    it 'turns away a signed-in user who is not an admin' do
      sign_in member

      get admin_cable_path

      expect(response).to redirect_to(root_path)
    end

    it 'turns away a signed-out visitor' do
      get admin_cable_path

      expect(response).to have_http_status(:redirect)
    end

    # The same terms as the rest of /admin: rearranging the dial is the admin's own job, not
    # part of what they are looking at when viewing the site as somebody else.
    it 'is gone while an admin is viewing the site as somebody else' do
      sign_in admin
      post impersonate_user_path(member)

      get admin_cable_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'the dial' do
    it 'lists the channels in dial order, numbered by their place on it' do
      sign_in admin

      get admin_cable_path

      expect(response.body.index('Channel One')).to be < response.body.index('Channel Two')
    end

    # Nothing on this page edits a channel's contents, so the name is the way to the page
    # that does.
    it 'links each channel name to the channel itself' do
      sign_in admin

      get admin_cable_path

      expect(response.body).to include(list_path(one))
      expect(response.body).to include(list_path(two))
    end

    # A channel with no schedule for today shows every viewer an off-air card and nothing
    # else says so.
    it 'says which channels have nothing laid out for today' do
      CableSchedule.build_day!(one, CableSchedule.today)
      sign_in admin

      get admin_cable_path

      expect(response.body).to include('Off air')
    end

    it 'offers the way to the reels and the providers a dead channel is fixed from' do
      sign_in admin

      get admin_cable_path

      expect(response.body).to include(admin_commercial_reels_path)
      expect(response.body).to include(sources_path)
    end

    # The button that used to be the guide's only admin control.
    it 'carries the rebuild button' do
      sign_in admin

      get admin_cable_path

      expect(response.body).to include(cable_regenerate_path)
    end
  end

  describe 'reordering the dial' do
    it 'puts the channels in the order they were dragged into' do
      sign_in admin

      patch reorder_admin_cable_channels_path, params: { ids: [two.id, one.id] }

      expect(response).to have_http_status(:no_content)
      expect(CableSchedule.channels.pluck(:id)).to eq([two.id, one.id])
    end

    # The order is renumbered 1..N on every drag, which is what repairs a gap or a collision
    # left by an earlier write.
    it 'renumbers from one, so a gap left earlier is closed' do
      one.update!(cable_position: 40)
      two.update!(cable_position: 40)
      sign_in admin

      patch reorder_admin_cable_channels_path, params: { ids: [two.id, one.id] }

      expect([two.reload.cable_position, one.reload.cable_position]).to eq([1, 2])
    end

    # A channel taken off the dial in another tab should not make the drag already on screen
    # fail.
    it 'ignores an id that is not on the dial' do
      sign_in admin

      patch reorder_admin_cable_channels_path, params: { ids: [two.id, candidate.id, one.id] }

      expect(response).to have_http_status(:no_content)
      expect(CableSchedule.channels.pluck(:id)).to eq([two.id, one.id])
      expect(candidate.reload.cable_position).to be_nil
    end

    it 'refuses a member' do
      sign_in member

      patch reorder_admin_cable_channels_path, params: { ids: [two.id, one.id] }

      expect(CableSchedule.channels.pluck(:id)).to eq([one.id, two.id])
    end
  end

  describe 'putting a channel on the dial' do
    it 'marks it default and lands it at the end of the dial' do
      sign_in admin

      post admin_cable_channels_path, params: { list_id: candidate.id }

      expect(candidate.reload).to be_default
      expect(candidate.cable_position).to eq(3)
      expect(CableSchedule.channels.pluck(:id)).to eq([one.id, two.id, candidate.id])
    end

    # Every page that reads the schedule fills a day it finds empty, so this is not what
    # keeps the channel on air -- it is what stops the dial reading as off air between the
    # button and the first visit.
    it 'lays out today, so the new channel is on air immediately' do
      sign_in admin

      post admin_cable_channels_path, params: { list_id: candidate.id }

      expect(CableSlot.where(list: candidate, airs_on: CableSchedule.today)).to be_any
    end

    # A private channel on the dial would show every account a list its owner chose not to
    # share, so the check is on the request and not only on the dropdown.
    it 'refuses a private channel' do
      private_list = create(:list, user: admin, name: 'Mine Alone', private: true)
      sign_in admin

      post admin_cable_channels_path, params: { list_id: private_list.id }

      expect(private_list.reload).not_to be_default
      expect(flash[:alert]).to be_present
    end

    it 'refuses a member' do
      sign_in member

      post admin_cable_channels_path, params: { list_id: candidate.id }

      expect(candidate.reload).not_to be_default
    end
  end

  describe 'taking a channel off the dial' do
    it 'clears the flag and its place, so /cable stops offering it' do
      sign_in admin

      delete admin_cable_channel_path(two)

      expect(two.reload).not_to be_default
      expect(two.cable_position).to be_nil
      expect(CableSchedule.channels.pluck(:id)).to eq([one.id])
    end

    # The one thing this must not be mistaken for. Taking a channel off the dial is a
    # setting; the channel, its entries and everybody's subscription to it are somebody's
    # work.
    it 'deletes nothing and unsubscribes nobody' do
      # Already subscribed, and by the dial: a channel becoming default subscribes every
      # account to it, which is exactly the subscription that must survive coming off.
      subscriber = create(:user)
      Subscription.create_subscription(subscriber, two)
      sign_in admin

      delete admin_cable_channel_path(two)

      expect(List.exists?(two.id)).to be(true)
      expect(two.entries.count).to eq(1)
      expect(Subscription.exists?(user: subscriber, list: two)).to be(true)
    end

    # A channel put back on the same day keeps the day it was already playing rather than
    # being dealt a new one on top of viewers who were watching it, which is why the slots
    # are left where they are for prune! to sweep.
    it 'leaves the schedule it already had alone' do
      CableSchedule.build_day!(two, CableSchedule.today)
      slots = CableSlot.where(list: two, airs_on: CableSchedule.today).order(:position).pluck(:id)
      sign_in admin

      delete admin_cable_channel_path(two)

      expect(CableSlot.where(list: two, airs_on: CableSchedule.today).order(:position).pluck(:id))
        .to eq(slots)
    end

    it 'refuses a channel that was never on the dial' do
      sign_in admin

      delete admin_cable_channel_path(candidate)

      expect(response).to redirect_to(admin_cable_path)
      expect(flash[:alert]).to be_present
    end

    it 'refuses a member' do
      sign_in member

      delete admin_cable_channel_path(two)

      expect(two.reload).to be_default
    end
  end

  # The star on a channel's own page sets the same flag. It went through `update` before
  # there was an order to keep, which would have left a channel on the dial with no place
  # on it -- the two controls saying different things about the same dial.
  describe 'the star on the channel page' do
    it 'gives the channel a place on the dial when it sets the flag' do
      sign_in admin

      patch list_toggle_default_path(candidate)

      expect(candidate.reload).to be_default
      expect(candidate.cable_position).to eq(3)
    end

    it 'takes the place away again when it clears the flag' do
      sign_in admin

      patch list_toggle_default_path(two)

      expect(two.reload).not_to be_default
      expect(two.cable_position).to be_nil
    end
  end
end
