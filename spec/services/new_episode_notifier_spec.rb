# frozen_string_literal: true

require 'rails_helper'

# Which episodes count as released is NewEpisodeImporter's business and is covered there.
# This is who gets told, and that telling them happens once.
RSpec.describe NewEpisodeNotifier do
  let(:today) { Date.new(2026, 9, 14) }
  let(:owner) { create(:user) }
  let(:channel) { create(:list, user: owner, name: 'Funny') }
  let!(:show) do
    create(:entry, list: channel, media: 'series', name: 'Rick and Morty', imdb: 'tt2861424',
                   tmdb: '60625', season: 9).tap do |entry|
      entry.subentries.create!(season: 9, episode: 1, name: 'Held')
    end
  end

  let(:tmdb) do
    instance_double(TmdbService).tap do |tmdb|
      allow(tmdb).to receive_messages(
        fetch_show: { 'last_episode_to_air' => { 'season_number' => 9, 'episode_number' => 2 },
                      'seasons' => [{ 'season_number' => 9 }] },
        fetch_season: { 'episodes' => [
          { 'episode_number' => 1, 'air_date' => '2026-08-24', 'name' => 'Held', 'runtime' => 23 },
          { 'episode_number' => 2, 'air_date' => '2026-08-31', 'name' => 'Ricks Days', 'runtime' => 23 }
        ] },
        fetch_show_external_ids: { 'imdb_id' => 'tt2861424' }
      )
    end
  end

  def sweep = described_class.call(tmdb: tmdb, today: today)

  it 'tells the owner of the channel about the episode it added' do
    sweep

    notification = Notification.find_by(user: owner, kind: Notification::NEW_EPISODE)
    expect(notification.subject).to eq(show.subentries.find_by(episode: 2))
    expect(notification.data).to include('show' => 'Rick and Morty', 'list' => 'Funny', 'season' => 9,
                                         'episode' => 2, 'title' => 'Ricks Days', 'air_date' => '2026-08-31')
  end

  # On a default channel the subscribers are every account, most of whom never chose the show.
  it 'tells only the owner, not the people subscribed to the channel' do
    subscriber = create(:user)
    subscriber.subscribe_to!(channel)

    sweep

    expect(Notification.where(kind: Notification::NEW_EPISODE).pluck(:user_id)).to eq([owner.id])
  end

  it 'is something a member can see, not an admin warning' do
    sweep

    expect(Notification.visible_to(owner).count).to eq(1)
  end

  it 'says nothing the second time round, because nothing is new' do
    sweep

    expect { sweep }.not_to change(Notification, :count)
    expect(show.subentries.count).to eq(2)
  end

  it 'reports what it did' do
    result = sweep

    expect(result).to have_attributes(checked: 1, added: 1, notified: 1, failed: 0)
  end

  it 'leaves anything that is not a series alone' do
    create(:entry, list: channel, media: 'anime', name: 'Frieren', tmdb: '209867')
    create(:entry, list: channel, media: 'movie', name: 'Heat', tmdb: '949')

    expect(sweep.checked).to eq(1)
  end

  it 'carries on past a show TMDB fails on, and writes nothing for it' do
    broken = create(:entry, list: channel, media: 'series', name: 'Broken', imdb: 'tt0000002', tmdb: '1', season: 1)
    broken.subentries.create!(season: 1, episode: 1, name: 'Held')
    allow(tmdb).to receive(:fetch_show_external_ids).with('1')
                                                    .and_raise(TmdbService::RequestError, 'TMDB tv/1 returned 500')

    result = sweep

    expect(result).to have_attributes(checked: 2, added: 1, failed: 1)
    expect(broken.subentries.count).to eq(1)
  end
end
