require 'rails_helper'

# Playing a provider ourselves instead of framing its player.
#
# MEGA is the only one, and the whole point of it is what follows rather than the video:
# an element in our own document can be driven, so a MEGA entry finally has a position, a
# resume, the keyboard, the up-next card and a place in a watch party. Every one of those
# hangs off `sync_adapter` being present, so that is asserted here too -- it is the switch,
# and nothing downstream has a case for this provider without it.
RSpec.describe 'Playing a provider ourselves', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let!(:mega) do
    Source.create!(name: 'MEGA', kind: 'direct', active: true, position: 1,
                   templates: { 'default' => 'https://mega.nz/embed/%{source_key}' })
  end
  let(:entry) do
    create(:entry, list: list, name: 'Solaris', media: 'movie', imdb: nil, position: 1,
                   provider: mega, source_key: 'AbCd1234#KeYkEyKeYkEyKeYkEyKeYkEyKeYkEyKeYkE')
  end

  before { sign_in user }

  describe 'which providers it applies to' do
    it 'is MEGA, whose files are ours to decrypt' do
      expect(mega).to be_native
    end

    it 'is not a provider whose player we only frame' do
      vidsrc = Source.create!(name: 'Vidsrc2', kind: 'imdb', active: true, position: 2,
                              templates: { 'movie' => 'https://vidsrc.test/%{imdb}' })

      expect(vidsrc).not_to be_native
    end

    # The switch. Without an adapter, player_progress and player_keys both bail at connect
    # and the entry goes back to having no position, no resume and no keyboard.
    it 'gives MEGA an adapter, which is what turns the rest of the app on for it' do
      expect(mega.sync_adapter).to eq('mega')
      expect(mega).to be_syncable
    end
  end

  describe 'the address the element is pointed at' do
    it 'carries the file and the key as separate segments' do
      expect(mega.native_url_for(entry))
        .to eq('/mega/AbCd1234/KeYkEyKeYkEyKeYkEyKeYkEyKeYkEyKeYkE/video.mp4')
    end

    # `!900s1a` is a resume and an autoplay for MEGA's own player. A player of our own
    # takes its position from the page, so the option run is dropped rather than carried.
    it 'drops the option run an embed would need' do
      entry.update!(source_key: 'AbCd1234#KeYkEyKeYkEyKeYkEyKeYkEyKeYkEyKeYkE!900s1a')

      expect(mega.native_url_for(entry)).to end_with('/KeYkEyKeYkEyKeYkEyKeYkEyKeYkEyKeYkE/video.mp4')
    end

    # A link pasted without its fragment names a file that nothing will ever decrypt.
    it 'is nothing at all without a key' do
      entry.update!(source_key: 'AbCd1234')

      expect(mega.native_url_for(entry)).to be_nil
    end
  end

  describe 'the watch page' do
    it 'holds a video of its own rather than a frame' do
      get watch_entry_path(entry)

      expect(response.body).to include('<video id="cinema"')
      expect(response.body).not_to include('<iframe id="cinema"')
    end

    # Handed over rather than written into the element: the service worker has to be in
    # control before the element asks for a byte, so native_player sets the src.
    it 'hands the address to the controller instead of writing it as a src' do
      get watch_entry_path(entry)

      expect(response.body).to include('data-controller="native-player"')
      expect(response.body).to include('data-native-player-src-value="/mega/AbCd1234/')
    end

    it 'names the adapter, so position tracking and the keyboard attach' do
      get watch_entry_path(entry)

      expect(response.body).to include('data-player-adapter="mega"')
    end

    # An embed takes its resume in the URL. This one cannot -- the address is ours and has
    # no room for it -- so it travels separately and is applied once the length is known.
    it 'carries the resume position separately' do
      user_entry = UserEntry.find_or_create_by!(user: user, entry: entry)
      user_entry.update!(player_progress: 900)

      get watch_entry_path(entry)

      expect(response.body).to match(/data-native-player-start-value="\d+"/)
      expect(response.body).not_to include('data-native-player-start-value="0"')
    end

    it 'still frames a provider we only have an embed for' do
      vidsrc = Source.create!(name: 'Vidsrc2', kind: 'imdb', active: true, position: 2,
                              templates: { 'movie' => 'https://vidsrc.test/movie/%{imdb}' })
      framed = create(:entry, list: list, media: 'movie', imdb: 'tt7', position: 2, provider: vidsrc)

      get watch_entry_path(framed)

      expect(response.body).to include('<iframe id="cinema"')
      expect(response.body).not_to include('<video id="cinema"')
    end
  end

  # The isolated page can show either, which is how the two get compared on one file.
  describe 'the isolated page' do
    it 'plays it ourselves by default' do
      get watch_only_entry_path(entry)

      expect(response.body).to include('<video id="player"')
    end

    it 'puts the provider’s own player back when asked' do
      get watch_only_entry_path(entry, player: 'embed')

      expect(response.body).to include('<iframe id="player"')
      expect(response.body).to include('mega.nz/embed/')
    end
  end
end
