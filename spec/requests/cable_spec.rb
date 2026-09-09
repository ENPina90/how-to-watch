require 'rails_helper'

# /cable is a channel already running when you turn it on. The two things that make it that
# rather than a playlist: it joins the programme partway through, at the point the clock
# says, and it records nothing about the viewer for having been on.
RSpec.describe 'Cable', type: :request do
  include CableHelper

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

  # The gap after a film, filled with adverts from its own year. The guide and the banner
  # both go on naming the programme -- the break falls under it, which is what keeps the
  # listing's start times tidy and is how a channel has always described itself.
  describe 'a commercial break' do
    let!(:youtube) do
      Source.create!(name: 'YouTube', slug: 'youtube', kind: 'direct', active: true, position: 9,
                     templates: { 'default' => 'https://www.youtube.com/embed/%{source_key}' })
    end
    let!(:reel) do
      CommercialReel.create!(label: '1998', starts_year: 1998, ends_year: 1998, youtube_id: 'reel98')
    end

    # A film ending at 00:47 in a slot that runs to 00:50.
    let(:slot) { CableSlot.where(list: channel).in_order.first }

    before do
      entry.update!(year: 1998, length: 47)
      CableSchedule.build_day!(channel, date)
      sign_in user
    end

    it 'plays the film before the break' do
      travel_to(midnight + 40.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('framerelay').or include('p.test')
      expect(response.body).not_to include('youtube.com/embed')
    end

    it 'plays the adverts once the film has ended' do
      travel_to(midnight + 48.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include("youtube.com/embed/#{reel.youtube_id}")
      # One minute into the break, one minute further into the reel.
      expect(response.body).to include("start=#{slot.break_offset + 60}")
    end

    it 'goes on naming the programme, not the adverts' do
      travel_to(midnight + 48.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include(entry.name)
      expect(response.body).not_to include('1998 commercials')
    end

    # Nothing here can drive a YouTube embed, and saying otherwise would leave the channel
    # below warmed into a player nobody can quieten.
    it 'claims no player adapter through the break' do
      travel_to(midnight + 48.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('data-player-adapter=""')
    end

    it 'sets the clock to the start of the break, then to the next programme' do
      travel_to(midnight + 40.minutes) { get cable_channel_path(channel) }
      expect(response.body).to include(slot.break_starts_at.utc.iso8601)

      travel_to(midnight + 48.minutes) { get cable_channel_path(channel) }
      expect(response.body).to include(slot.ends_at.utc.iso8601)
    end

    # A real channel cuts to the adverts rather than sitting on a finished player until the
    # clock catches up.
    it 'cuts to the adverts when the player says the film finished early' do
      travel_to(midnight + 40.minutes) { get cable_channel_path(channel, filler: 1) }

      expect(response.body).to include("youtube.com/embed/#{reel.youtube_id}")
    end

    # A reel can stop being playable between one break and the next -- taken down, made
    # private, embedding switched off, or simply refused for the moment. The player says so
    # only to whoever asks it to listen; without that the viewer gets a black rectangle
    # reading "This video is unavailable" for the length of the break.
    it 'asks the reel to report back, so a refusal can be heard' do
      travel_to(midnight + 48.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('enablejsapi=1')
      expect(response.body).to include('cable-filler')
    end

    # Rendered for every break rather than only the ones that start out empty: it is what
    # the page uncovers when the reel refuses, so it has to already be there.
    it 'carries the caption through every break, ready but hidden' do
      travel_to(midnight + 48.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('id="cableInterlude"')
      expect(response.body[/<div id="cableInterlude"[^>]*>/]).to include('hidden')
    end

    it 'watches for a refusal only while a break is running' do
      travel_to(midnight + 40.minutes) { get cable_channel_path(channel) }

      expect(response.body).not_to include('cable-filler')
      expect(response.body).not_to include('id="cableInterlude"')
    end

    it 'puts a caption up when the period has no adverts' do
      CommercialReel.delete_all
      CableSchedule.build_day!(channel, date)

      travel_to(midnight + 48.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('cable-interlude')
      # Shown from the start this time -- there was never anything to hide it behind.
      expect(response.body[/<div id="cableInterlude"[^>]*>/]).not_to include('hidden')
      expect(response).to be_successful
    end

    # The bug this was written for: arriving after the file has ended but before the slot
    # has. The player, handed a start position past the end, does not refuse and does not
    # stop -- it starts the film again from the beginning. The page spots the overrun from
    # the length the player reports and asks for filler; this is the answer it gets.
    it 'serves adverts on a slot with no scheduled gap when the page asks for filler' do
      entry.update!(year: 1998, length: 45)
      CableSchedule.build_day!(channel, date)
      expect(CableSlot.where(list: channel).in_order.first.break_starts_at).to be_nil

      travel_to(midnight + 30.minutes) { get cable_channel_path(channel, filler: 1) }

      expect(response.body).to include("youtube.com/embed/#{reel.youtube_id}")
    end

    # Without it the page has no way to tell where the schedule thinks the film is, and so
    # no way to notice that the file is shorter than the catalogue claims.
    it 'tells the page where the programme started' do
      travel_to(midnight + 40.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include(
        %(data-cable-clock-programme-starts-at-value="#{slot.starts_at.utc.iso8601}")
      )
    end

    it 'moves on to the next programme when the break is over' do
      travel_to(midnight + 51.minutes) { get cable_channel_path(channel) }

      expect(response.body).not_to include("youtube.com/embed/#{reel.youtube_id}")
    end
  end

  # The cable page's next programme is not at an address of its own -- it is this same
  # channel, asked what will be on at the moment it changes. That is how it warms the next
  # programme before it starts, the way the watch page warms its next entry.
  describe 'asking what will be on in a moment' do
    before { sign_in user }

    def warming(path)
      get path, headers: { 'X-Cinema-Preload' => '1', 'X-Requested-With' => 'XMLHttpRequest' }
    end

    it 'answers with the programme that will be on then' do
      travel_to(midnight + 10.minutes) do
        slot = CableSchedule.on_air(channel, at: Time.current)
        following = CableSlot.where(list: channel).after(slot.ends_at).in_order.first

        warming(cable_channel_path(channel, at: slot.ends_at.to_i))

        expect(response.body).to include(following.entry.name)
      end
    end

    it 'names that address on the page, so the warming knows where to look' do
      travel_to(midnight + 10.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('data-cinema-next-url')
    end

    # A channel somebody is actually watching cannot be made to claim something else is on.
    # The whole point of the parameter is that nobody is looking at that copy of the page.
    it 'ignores the time on a page somebody is watching' do
      travel_to(midnight + 10.minutes) do
        on_now = CableSchedule.on_air(channel, at: Time.current)
        slot_end = on_now.ends_at

        get cable_channel_path(channel, at: slot_end.to_i)

        expect(response.body).to include(on_now.entry.name)
      end
    end

    it 'ignores a time that has already gone' do
      travel_to(midnight + 40.minutes) do
        on_now = CableSchedule.on_air(channel, at: Time.current)

        warming(cable_channel_path(channel, at: (Time.current - 20.minutes).to_i))

        expect(response.body).to include(on_now.entry.name)
      end
    end

    # However far ahead the next change happens to be. A film runs two hours; the address
    # the page prints for itself has to still mean something when the warming finally uses
    # it, which is why this is not bounded by how near the time is.
    it 'answers however far ahead the change is' do
      travel_to(midnight) do
        long = CableSchedule.on_air(channel, at: Time.current)
        following = CableSlot.where(list: channel).after(long.ends_at).in_order.first

        warming(cable_channel_path(channel, at: long.ends_at.to_i))

        expect(response.body).to include(following.entry.name)
      end
    end

    it 'records nothing about the viewer when asked' do
      counts = -> { [UserListPosition.count, UserEntry.count, UserEntryPosition.count] }

      travel_to(midnight + 10.minutes) do
        before_counts = counts.call
        slot = CableSchedule.on_air(channel, at: Time.current)

        warming(cable_channel_path(channel, at: slot.ends_at.to_i))

        expect(counts.call).to eq(before_counts)
      end
    end
  end

  # The schedule is only as good as the runtimes it is laid out from, and it cannot see them
  # for itself. The page carries what the catalogue claims and, where it claims nothing, the
  # address to say otherwise.
  describe 'correcting a runtime the catalogue does not have' do
    it 'offers the correction when the catalogue is silent' do
      entry.update!(length: nil)
      CableSchedule.build_day!(channel, date)
      sign_in user

      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('data-cable-clock-runtime-value="0"')
      expect(response.body).to include(runtime_entry_path(entry))
    end

    it 'says what the catalogue claims when it has one' do
      sign_in user

      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include(%(data-cable-clock-runtime-value="#{entry.length * 60}"))
    end

    # Correcting the catalogue is a write, and a guest has no way to make one.
    it 'offers a visitor with no account nowhere to send it' do
      AppSetting.update_access_mode!('open')
      entry.update!(length: nil)
      CableSchedule.build_day!(channel, date)

      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response).to be_successful
      expect(response.body).not_to include('data-cable-clock-runtime-url-value')
    end
  end

  describe 'the channel banner' do
    before { sign_in user }

    it 'shows the channel by its dial number' do
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('cable-hud__number')
      expect(response.body).to include(">#{CableSchedule.dial_number(channel)}<")
    end

    # The same pair the guide's panel offers: the channel to its own page, the programme to
    # the ordinary player, where it plays from the beginning and counts as watched.
    it 'links the channel to its page and the programme to the watch player' do
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include(%(class="cable-hud__channel" href="#{list_path(channel)}"))
      expect(response.body).to include(watch_entry_path(entry, channel: channel.id))
    end

    it 'carries the running order the peek arrows walk' do
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include('data-slot-start=').and include('data-slot-current="true"')
    end

    # The whole point of the left and right arrows: they say what came before and what is
    # coming, and they change nothing. A cinema-move on either would tune the channel, which
    # is exactly what a schedule means you cannot do.
    it 'gives the peek arrows no way to tune' do
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      peeks = response.body.scan(%r{<button[^>]*cable-hud__key--(?:left|right)[^>]*>})
      expect(peeks.length).to eq(2)
      peeks.each do |arrow|
        expect(arrow).not_to include('data-cinema-move')
        expect(arrow).not_to include('href')
      end
    end

    # Up and down still do, and down is still the one worth warming.
    it 'keeps the channel arrows as moves' do
      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response.body).to include(cable_channel_path(CableSchedule.sibling(channel, :next)))
      expect(response.body).to include('data-cinema-preload')
    end

    it 'gives a signed-out visitor no way to mark anything watched' do
      sign_out user
      AppSetting.update_access_mode!('open')

      travel_to(midnight + 11.minutes) { get cable_channel_path(channel) }

      expect(response).to be_successful
      expect(response.body).not_to include('completion-status')
    end
  end

  describe 'the guide' do
    let!(:second_channel) do
      create(:list, user: user, provider: provider, default: true, name: 'Channel Two')
    end
    let!(:second_entry) do
      create(:entry, list: second_channel, name: 'Something Else', media: 'movie',
                     length: 45, position: 1, imdb: 'tt0000002')
    end

    before { CableSchedule.build_day!(second_channel, date) }

    # "guide" is a word, and /cable/:id takes anything. Without the guide route declared
    # first the word is cast to a channel id, comes back as nothing, and the dial's first
    # channel is served instead -- a page, with no error, that is simply not the guide.
    it 'is the guide rather than a channel called "guide"' do
      sign_in user
      travel_to(midnight + 11.minutes) { get cable_guide_path }

      expect(response).to be_successful
      expect(response.body).to include('tvguide__grid')
      expect(response.body).not_to include('cinema-chrome')
    end

    it 'lists every channel on the dial with its dial number' do
      sign_in user
      travel_to(midnight + 11.minutes) { get cable_guide_path }

      expect(response.body).to include('Channel One').and include('Channel Two')
      expect(response.body).to include('The Death of Harvey').and include('Something Else')
    end

    it 'marks the channel it was opened from' do
      sign_in user
      travel_to(midnight + 11.minutes) do
        get cable_guide_path, params: { channel: second_channel.id }
      end

      expect(response.body).to include('tvguide__row--tuned')
    end

    # The window runs four hours, so from mid-evening it reaches into tomorrow. A grid that
    # stopped dead at midnight would be the guide going blank exactly when it is most used.
    it 'lays out tomorrow when the window reaches into it' do
      late = CableSchedule.zone.local(2026, 9, 10, 22, 30)

      sign_in user
      expect { travel_to(late) { get cable_guide_path } }
        .to change { CableSlot.where(airs_on: date + 1).count }.from(0)

      expect(response).to be_successful
    end

    it 'records nothing about the viewer' do
      sign_in user
      counts = -> { [UserListPosition.count, UserEntry.count, UserEntryPosition.count] }
      before_counts = counts.call

      travel_to(midnight + 11.minutes) { get cable_guide_path }

      expect(counts.call).to eq(before_counts)
    end

    # The columns and the clock are labelled in the viewer's zone, so the listing agrees
    # with the clock in the room they are sitting in. The schedule itself does not move --
    # these are the same instants, read from somewhere else.
    it 'labels the listing in the zone the viewer says they are in' do
      sign_in user
      travel_to(midnight + 11.minutes) do
        get cable_guide_path, params: { tz: 'Europe/Berlin' }
      end

      berlin = CableSchedule.guide_window(at: midnight + 11.minutes,
                                          in_zone: ActiveSupport::TimeZone['Europe/Berlin'])
      expect(response.body).to include(cable_time(berlin.begin, ActiveSupport::TimeZone['Europe/Berlin']).upcase)
    end

    it 'falls back to the schedule zone when the browser sends nonsense' do
      sign_in user
      travel_to(midnight + 11.minutes) { get cable_guide_path, params: { tz: 'Mars/Olympus' } }

      expect(response).to be_successful
    end

    # The grid is fetched once and read for as long as somebody leaves it up, so the cells
    # have to carry their own times -- the clock, the line across the grid and the cell it
    # marks are all worked out in the browser from these.
    it 'gives every programme the marks the clock needs' do
      sign_in user
      travel_to(midnight + 11.minutes) { get cable_guide_path }

      expect(response.body).to include('data-guide-start=').and include('data-guide-end=')
      expect(response.body).to include('data-window-start=')
    end

    it 'says which programmes this viewer has already seen' do
      entry.mark_completed_by!(user)

      sign_in user
      travel_to(midnight + 11.minutes) { get cable_guide_path }

      expect(response.body).to include('data-guide-watched="true"')
      expect(response.body).to include('data-guide-watched="false"')
    end

    it 'tells a signed-out visitor nothing about what anyone has seen' do
      AppSetting.update_access_mode!('open')
      entry.mark_completed_by!(user)

      travel_to(midnight + 11.minutes) { get cable_guide_path }

      expect(response).to be_successful
      expect(response.body).not_to include('data-guide-watched="true"')
    end

    it 'links each programme out to its own page and its channel' do
      sign_in user
      travel_to(midnight + 11.minutes) { get cable_guide_path }

      expect(response.body).to include("data-guide-watch-url=\"#{watch_entry_path(entry, channel: channel.id)}")
      expect(response.body).to include("data-guide-channel-url=\"#{list_path(channel)}\"")
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
