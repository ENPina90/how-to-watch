# frozen_string_literal: true

require 'rails_helper'

# A playlist into a channel. The reading is YoutubePlaylist's and is stubbed out here; what
# is left is what each video becomes, and that running it twice does not double a channel.
RSpec.describe YoutubePlaylistImporter do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Podcasts') }
  let!(:youtube) do
    Source.create!(name: 'YouTube', slug: 'youtube', kind: 'direct', active: true,
                   templates: { 'default' => 'https://www.youtube.com/embed/%{source_key}' })
  end

  let(:url) { 'https://www.youtube.com/playlist?list=PLYi6bn_TN8EK-Y3W5ytMPTehcaUUIYA1R' }

  def video(id, title:, seconds: 3830, embeddable: true, age_restricted: false,
            description: "Henry, Ben and Marcus discuss axe attacks.\n\nSUBSCRIBE: https://example.test")
    YoutubePlaylist::Video.new(
      youtube_id: id, title: title, description: description, duration_seconds: seconds,
      thumbnail_url: "https://i.ytimg.com/vi/#{id}/maxresdefault.jpg",
      published_at: Time.utc(2021, 7, 23), embeddable: embeddable, age_restricted: age_restricted
    )
  end

  def playlist(*videos, unavailable: 0, title: 'Last Stream on the Left full episodes')
    YoutubePlaylist::Playlist.new(id: 'PL1', title: title, videos: videos, unavailable: unavailable)
  end

  def import(from)
    allow(YoutubePlaylist).to receive(:fetch).with(url).and_return(from)
    described_class.new(url: url, list: list).call
  end

  it 'makes an entry of each video that plays from YouTube' do
    result = import(playlist(video('0_paCykOQNI', title: 'Last Stream on the Left - S1 EP1 - August 12, 2016')))

    expect(result.summary).to eq('1 video added from Last Stream on the Left full episodes')
    entry = list.entries.sole
    expect(entry).to have_attributes(
      name: 'Last Stream on the Left - S1 EP1 - August 12, 2016',
      provider: youtube,
      source_key: '0_paCykOQNI',
      length: 64,
      year: 2021,
      pic: 'https://i.ytimg.com/vi/0_paCykOQNI/maxresdefault.jpg',
      position: 1
    )
    expect(entry.embed_url).to eq('https://www.youtube.com/embed/0_paCykOQNI?enablejsapi=1')
  end

  # What follows the first paragraph is links and "subscribe".
  it 'takes the first paragraph of the description as the plot' do
    import(playlist(video('aaaaaaaaaaa', title: 'A video')))

    expect(list.entries.sole.plot).to eq('Henry, Ben and Marcus discuss axe attacks.')
  end

  it 'files a video numbered in its title as an episode of the playlist' do
    import(playlist(video('aaaaaaaaaaa', title: 'Last Stream On The Left | S8 Ep9: Dumbutainment | Adult Swim')))

    expect(list.entries.sole).to have_attributes(
      media: 'episode', series: 'Last Stream on the Left full episodes', season: 8, episode: 9,
      category: 'Last Stream on the Left full episodes'
    )
  end

  {
    'Show - S1 EP1 - August 12, 2016' => [1, 1],
    'Show S01E02' => [1, 2],
    'Show: Season 2 Episode 10' => [2, 10]
  }.each do |title, (season, episode)|
    it "reads #{title.inspect} as S#{season}E#{episode}" do
      import(playlist(video('aaaaaaaaaaa', title: title)))

      expect(list.entries.sole).to have_attributes(season: season, episode: episode)
    end
  end

  it 'files a video with no number in its title as a standalone video' do
    import(playlist(video('aaaaaaaaaaa', title: 'Behind the scenes')))

    expect(list.entries.sole).to have_attributes(media: 'fanedit', series: nil, season: nil,
                                                 category: 'Last Stream on the Left full episodes')
  end

  it 'keeps playlist order, after whatever the channel already holds' do
    create(:entry, list: list, name: 'Already here', position: 4)

    import(playlist(video('aaaaaaaaaaa', title: 'First'), video('bbbbbbbbbbb', title: 'Second')))

    expect(list.entries.where(provider: youtube).order(:position).pluck(:name, :position))
      .to eq([['First', 5], ['Second', 6]])
  end

  # A playlist that has grown since is imported again, and only the new videos should land.
  it 'leaves alone a video the channel already has, however its id was pasted' do
    create(:entry, list: list, name: 'Hand-made', media: 'fanedit', imdb: nil,
                   provider: youtube, source_key: 'aaaaaaaaaaa?si=0P0rhhlLZ9J2F42S')

    result = import(playlist(video('aaaaaaaaaaa', title: 'Old'), video('bbbbbbbbbbb', title: 'New')))

    expect(result.created.map(&:name)).to eq(['New'])
    expect(result.notes).to include('1 already in Podcasts')
  end

  it 'leaves out a video whose owner switched embedding off, and says which' do
    result = import(playlist(video('aaaaaaaaaaa', title: 'Blocked', embeddable: false)))

    expect(list.entries).to be_empty
    expect(result.notes.join).to include('embedding is switched off', 'Blocked')
  end

  it 'adds an age-restricted video, and says YouTube may refuse it' do
    result = import(playlist(video('aaaaaaaaaaa', title: 'Restricted', age_restricted: true)))

    expect(list.entries.sole.name).to eq('Restricted')
    expect(result.notes.join).to include('Age-restricted', 'Restricted')
  end

  it 'counts the private and deleted videos it could not read' do
    result = import(playlist(video('aaaaaaaaaaa', title: 'Here'), unavailable: 2))

    expect(result.notes).to include('2 private or deleted videos left out')
  end

  # One bad video is a note, not the end of the import.
  it 'reports a video that will not save and carries on' do
    result = import(playlist(video('aaaaaaaaaaa', title: 'S1 EP1 - Same'),
                             video('bbbbbbbbbbb', title: 'S1 EP1 - Same'),
                             video('ccccccccccc', title: 'S1 EP2 - Different')))

    expect(result.created.map(&:name)).to eq(['S1 EP1 - Same', 'S1 EP2 - Different'])
    expect(result.notes.join).to include('Name has already been taken')
  end

  it 'passes on what YouTube would not give it' do
    allow(YoutubePlaylist).to receive(:fetch)
      .and_raise(YoutubePlaylist::RequestError, 'YouTube has no public playlist at that link')

    result = described_class.new(url: url, list: list).call

    expect(result.created).to be_empty
    expect(result.notes).to eq(['YouTube has no public playlist at that link'])
  end

  it 'does not ask YouTube when there is no provider to play the videos through' do
    youtube.update!(active: false)
    allow(YoutubePlaylist).to receive(:fetch)

    result = described_class.new(url: url, list: list).call

    expect(result.notes.join).to include('no active YouTube provider')
    expect(YoutubePlaylist).not_to have_received(:fetch)
  end
end
