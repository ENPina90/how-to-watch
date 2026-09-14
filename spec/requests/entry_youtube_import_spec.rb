# frozen_string_literal: true

require 'rails_helper'

# Pasting a YouTube playlist on the custom-entry page. What the videos become is
# YoutubePlaylistImporter's; this is who may do it, and what they are told.
RSpec.describe 'Entry YouTube import', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Podcasts') }
  let(:url) { 'https://www.youtube.com/playlist?list=PLYi6bn_TN8EK-Y3W5ytMPTehcaUUIYA1R' }

  before do
    sign_in user
    Source.create!(name: 'YouTube', slug: 'youtube', kind: 'direct', active: true,
                   templates: { 'default' => 'https://www.youtube.com/embed/%{source_key}' })
  end

  def video(id, title)
    YoutubePlaylist::Video.new(youtube_id: id, title: title, duration_seconds: 3600,
                               embeddable: true, age_restricted: false)
  end

  def playlist(*videos, unavailable: 0)
    YoutubePlaylist::Playlist.new(id: 'PL1', title: 'Last Stream on the Left', videos: videos,
                                  unavailable: unavailable)
  end

  it 'adds the videos to the channel and says what it did' do
    allow(YoutubePlaylist).to receive(:fetch).with(url).and_return(playlist(video('aaaaaaaaaaa', 'S1 EP1')))

    post import_youtube_list_entries_path(list), params: { playlist_url: url }

    expect(response).to redirect_to(list_path(list))
    expect(flash[:notice]).to eq('1 video added from Last Stream on the Left')
    expect(list.entries.sole.source_key).to eq('aaaaaaaaaaa')
  end

  it 'reports what it left out alongside what it added' do
    allow(YoutubePlaylist).to receive(:fetch).and_return(playlist(video('aaaaaaaaaaa', 'S1 EP1'), unavailable: 1))

    post import_youtube_list_entries_path(list), params: { playlist_url: url }

    expect(flash[:alert]).to include('1 private or deleted video left out')
  end

  it 'comes back to the form when nothing could be added' do
    allow(YoutubePlaylist).to receive(:fetch)
      .and_raise(YoutubePlaylist::RequestError, 'YouTube has no public playlist at that link')

    post import_youtube_list_entries_path(list), params: { playlist_url: url }

    expect(response).to redirect_to(new_list_entry_path(list))
    expect(flash[:alert]).to include('no public playlist')
    expect(list.entries).to be_empty
  end

  # A playlist writes as many rows as it has videos, so like the spreadsheet it asks first
  # whose channel it is filling.
  it 'refuses a channel the member cannot edit, without asking YouTube' do
    other = create(:list, user: create(:user))
    allow(YoutubePlaylist).to receive(:fetch)

    post import_youtube_list_entries_path(other), params: { playlist_url: url }

    expect(other.entries).to be_empty
    expect(flash[:alert]).to include('cannot add')
    expect(YoutubePlaylist).not_to have_received(:fetch)
  end

  # CSRF tokens do not protect GET, so an import reachable over one would let a prefetch fill
  # a channel.
  it 'does not import over GET' do
    get "/lists/#{list.id}/entries/import_youtube"

    expect(response).to have_http_status(:not_found)
  end
end
