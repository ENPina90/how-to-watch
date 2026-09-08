require 'rails_helper'

# /cable is a channel already running when you turn it on. The two things that make it that
# rather than a playlist: it joins the programme partway through, at the point the clock
# says, and it records nothing about the viewer for having been on.
RSpec.describe 'Cable', type: :request do
  let(:user) { create(:user) }

  let!(:provider) do
    Source.create!(
      name: 'Primary', kind: 'imdb', active: true, position: 1, autoplay_param: 'autoplay',
      templates: { 'movie' => 'https://p.test/movie?imdb=%{imdb}' }
    )
  end

  let!(:channel) { create(:list, user: user, provider: provider, default: true, name: 'Channel One') }
  let!(:entry) do
    create(:entry, list: channel, name: 'The Death of Harvey', media: 'movie',
                   length: 90, position: 1, imdb: 'tt0000001')
  end

  let(:date) { Date.new(2026, 9, 10) }
  let(:midnight) { CableSchedule.zone.local(2026, 9, 10) }

  before { CableSchedule.build_day!(channel, date) }

  describe 'turning a channel on' do
    it 'plays what the schedule says, from where the clock says' do
      travel_to(midnight + 11.minutes) do
        sign_in user
        get cable_channel_path(channel)
      end

      expect(response).to be_successful
      expect(response.body).to include('The Death of Harvey')
      # The provider's resume parameter is absent from this template's provider, so the
      # position is asserted where it is decided instead.
      slot = CableSchedule.on_air(channel, at: midnight + 11.minutes)
      expect(slot.offset_at(midnight + 11.minutes)).to eq(660)
    end

    it 'bakes the position into the embed URL on a provider that takes one' do
      provider.update!(slug: 'vidsrc2')

      travel_to(midnight + 11.minutes) do
        sign_in user
        get cable_channel_path(channel)
      end

      expect(response.body).to include('startAt=660')
    end

    it 'defaults to the first channel on the dial' do
      sign_in user
      travel_to(midnight + 5.minutes) { get cable_path }
      expect(response).to be_successful
      expect(response.body).to include('Channel One')
    end

    it 'lands on the first channel rather than 404ing for a channel not on the dial' do
      off_dial = create(:list, user: user, provider: provider, default: false)

      sign_in user
      travel_to(midnight + 5.minutes) { get cable_channel_path(off_dial) }

      expect(response).to be_successful
      expect(response.body).to include('Channel One')
    end
  end

  describe 'what it does not record' do
    it 'writes no position, no tracking row and no episode pointer' do
      sign_in user

      counts = -> { [UserListPosition.count, UserEntry.count, UserEntryPosition.count] }
      before = counts.call

      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(counts.call).to eq(before)
    end

    it 'leaves an existing position where it was' do
      position = channel.position_for_user!(user)
      position.update!(current_position: 7)

      sign_in user
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(position.reload.current_position).to eq(7)
    end
  end

  describe 'a schedule nobody laid out' do
    it 'fills the day on demand rather than showing a dead channel' do
      CableSlot.delete_all

      sign_in user
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response).to be_successful
      expect(CableSlot.where(list: channel)).to be_any
    end

    it 'does not lay one out for a channel that is only being warmed' do
      CableSlot.delete_all

      sign_in user
      travel_to(midnight + 11.minutes) do
        get cable_channel_path(channel), headers: { 'X-Cinema-Preload' => '1' }
      end

      expect(CableSlot.count).to be_zero
    end
  end

  describe 'a channel with nothing it can play' do
    it 'says it is off air and still offers the rest of the dial' do
      CableSlot.delete_all
      entry.update!(imdb: nil, source_key: nil)

      sign_in user
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response).to be_successful
      expect(response.body).to include('Off air')
    end
  end
end
