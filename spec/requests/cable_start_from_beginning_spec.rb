require 'rails_helper'

# A cable channel drops you into a film that started twenty minutes ago. Wanting it from the
# top is the commonest thing anybody asks of one, and until now the only way to say so was to
# guess that the banner's headline happened to be a link.
#
# Both buttons lead out of cable to the ordinary watch player, where the film plays from the
# beginning and counts towards what the viewer has seen.
RSpec.describe 'Start from the beginning', type: :request do
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

  before do
    CableSchedule.build_day!(channel, date)
    sign_in user
  end

  describe 'on the channel banner' do
    it 'offers a button wired to the programme the banner is describing' do
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('cable-hud__start')
      expect(response.body).to include('data-cable-hud-target="start"')
    end

    # The banner's arrows walk the running order without tuning, so the button has to follow
    # them -- it is the address of whichever programme is being described, which is what the
    # rendered schedule carries per slot.
    it 'gets its address from the running order the arrows walk' do
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      slot = CableSchedule.on_air(channel, at: midnight + 11.minutes)

      expect(response.body).to include(
        %(data-slot-url="#{watch_entry_path(slot.entry, channel: channel.id)}")
      )
    end
  end

  describe 'in the guide' do
    it 'offers a button in the panel beside the picture' do
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('data-cable-guide-target="detailStart"')
      expect(response.body).to include('Start from the beginning')
    end

    # The grid already carried the address for its heading; the button reads the same one,
    # so a cell pointed at anywhere in the listing can be started from the top.
    it 'takes its address from the cell being pointed at' do
      travel_to(midnight + 11.minutes) { get cable_guide_path }

      slot = CableSchedule.on_air(channel, at: midnight + 11.minutes)

      expect(response.body).to include(
        %(data-guide-watch-url="#{watch_entry_path(slot.entry, channel: channel.id)}")
      )
    end
  end

  # Out of cable rather than a tune: neither button carries data-cinema-move, so both are
  # ordinary navigations and the watch page records the position the way it always does.
  it 'lands on the watch page, which starts the film from the beginning' do
    get watch_entry_path(entry, channel: channel.id)

    expect(response).to be_successful
    expect(response.body).to include('The Death of Harvey')
  end
end
