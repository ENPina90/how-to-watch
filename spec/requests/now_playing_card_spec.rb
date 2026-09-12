require 'rails_helper'

# The sidebar's Now Playing card. Two things can honestly be called that, and which one it
# is depends on whether there is a picture on the screen beside it: the player page has one,
# every other page does not, and cable is the only thing in the app that is on regardless of
# who is looking.
RSpec.describe 'The Now Playing card', type: :request do
  let(:user) { create(:user) }

  let!(:provider) do
    Source.create!(
      name: 'Primary', kind: 'imdb', active: true, position: 1, autoplay_param: 'autoplay',
      templates: { 'movie' => 'https://p.test/movie?imdb=%{imdb}' }
    )
  end

  let!(:channel) { create(:list, user: user, provider: provider, default: true, name: 'Channel One') }
  let!(:on_air) do
    create(:entry, list: channel, name: 'The Death of Harvey', media: 'movie',
                   length: 90, position: 1, imdb: 'tt0000001')
  end

  let(:date) { Date.new(2026, 9, 10) }
  let(:midnight) { CableSchedule.zone.local(2026, 9, 10) }

  before do
    CableSchedule.build_day!(channel, date)
    sign_in user
  end

  describe 'away from the player' do
    it 'shows what is on the dial and tunes to that channel' do
      travel_to(midnight + 11.minutes) { get lists_path }

      expect(response.body).to include('The Death of Harvey')
      expect(response.body).to include("Ch 1 &middot; Channel One")
      expect(response.body).to include(%(href="#{cable_channel_path(channel)}"))
    end

    # The card used to show where the member had got to in some channel, which is a bookmark
    # rather than a programme -- the heading promised live and the card answered with a
    # resume point.
    it 'does not offer a resume point instead' do
      other = create(:list, user: user, name: 'Westerns')
      bookmark = create(:entry, list: other, name: 'Rio Bravo', media: 'movie', position: 1)
      other.position_for_user!(user).update!(current_position: bookmark.position)

      travel_to(midnight + 11.minutes) { get lists_path }

      card = response.body[/<div id="nowPlayingContent".*?<\/div>\s*<\/div>\s*<\/div>/m]

      expect(card).to include('The Death of Harvey')
      expect(card).not_to include('Rio Bravo')
    end

    # Nothing of this member's is playing and the whole dial is dark. A television puts up
    # the stand-by card, and so does this.
    it 'stands by when every channel is off air' do
      CableSlot.delete_all

      get lists_path

      expect(response.body).to include('Nothing playing')
      expect(response.body).not_to include('The Death of Harvey')
    end
  end

  # The player page has a picture on it and the card is a caption for that picture -- which
  # is also what cinema-navigation swaps when the viewer changes channel.
  describe 'on the player' do
    it 'keeps naming the film being watched' do
      watching = create(:entry, list: create(:list, user: user, provider: provider, name: 'Westerns'),
                                name: 'Rio Bravo', media: 'movie', position: 1, imdb: 'tt0053221')

      travel_to(midnight + 11.minutes) { get watch_entry_path(watching) }

      card = response.body[/<div id="nowPlayingContent".*?<\/div>\s*<\/div>\s*<\/div>/m]

      expect(card).to include('Rio Bravo')
      expect(card).not_to include('The Death of Harvey')
    end
  end

  # A rotation, so the whole dial gets seen from outside /cable rather than one channel for
  # ever. The place in it is the session's, so it advances as the member moves around.
  describe 'across several channels' do
    let!(:second_channel) { create(:list, user: user, provider: provider, default: true, name: 'Channel Two') }

    before do
      create(:entry, list: second_channel, name: 'Night Of The Comet', media: 'movie',
                     length: 90, position: 1, imdb: 'tt0087800')
      CableSchedule.build_day!(second_channel, date)
    end

    it 'moves along the dial from one page to the next' do
      seen = travel_to(midnight + 11.minutes) do
        3.times.map do
          get lists_path
          response.body.include?('Night Of The Comet') ? 'Channel Two' : 'Channel One'
        end
      end

      expect(seen.uniq.size).to eq(2)
    end
  end

  # Reading a listing is not watching it: drawing this card must not record that anybody was
  # up to anything.
  it 'records nothing about the viewer' do
    expect {
      travel_to(midnight + 11.minutes) { get lists_path }
    }.not_to change { [UserEntry.count, UserListPosition.count, UserEntryPosition.count] }
  end
end
