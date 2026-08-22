require 'rails_helper'

RSpec.describe SeasonImporter do
  let(:list) { create(:list) }

  let(:season_payload) do
    {
      'poster_path' => '/poster.jpg',
      'overview' => 'The first season.',
      'air_date' => '2019-04-06',
      'episodes' => [
        { 'episode_number' => 1, 'name' => 'Ep one', 'overview' => 'First',  'vote_average' => 8.0 },
        { 'episode_number' => 2, 'name' => 'Ep two', 'overview' => 'Second', 'vote_average' => 7.5 }
      ]
    }
  end

  let(:tmdb) do
    instance_double(TmdbService,
                    fetch_season: season_payload,
                    fetch_episode_external_ids: { 'imdb_id' => 'tt_ep' })
  end

  def importer(**overrides)
    described_class.new(**{
      list: list, tmdb_id: '1429', series_imdb_id: 'tt1355642',
      series_name: 'Attack on Titan', season: 1, tmdb: tmdb
    }.merge(overrides))
  end

  describe 'a series season' do
    it 'creates the parent entry and one subentry per episode' do
      result = importer.call

      expect(result[:status]).to eq(:created)
      expect(result[:episodes_added]).to eq(2)
      expect(result[:episodes_failed]).to be_empty

      entry = result[:entry]
      expect(entry.name).to eq('Attack on Titan - Season 1')
      expect(entry.media).to eq('series')
      expect(entry.year).to eq(2019)
      expect(entry.pic).to eq('https://image.tmdb.org/t/p/w500/poster.jpg')
      expect(entry.subentries.count).to eq(2)
    end

    it 'points the entry at its first episode' do
      entry = importer.call[:entry]

      expect(entry.current).to eq(entry.subentries.order(:episode).first)
    end

    it 'builds season/episode source urls' do
      entry = importer.call[:entry]

      expect(entry.subentries.order(:episode).first.source)
        .to eq('https://vidsrc.cc/v3/embed/tv/tt1355642/1/1')
    end

    it 'falls back to the series imdb id when an episode lookup fails' do
      allow(tmdb).to receive(:fetch_episode_external_ids).and_raise(TmdbService::RequestError, 'boom')

      entry = importer.call[:entry]

      expect(entry.subentries.pluck(:imdb).uniq).to eq(['tt1355642'])
    end
  end

  describe 'an anime season' do
    it 'numbers episodes continuously across seasons' do
      # Season 2 follows a 25-episode season 1, so its first episode is absolute 26.
      allow(tmdb).to receive(:fetch_season).with('1429', 1).and_return(
        season_payload.merge('episodes' => Array.new(25) { |i| { 'episode_number' => i + 1, 'name' => "E#{i + 1}" } })
      )
      allow(tmdb).to receive(:fetch_season).with('1429', 2).and_return(season_payload)

      entry = importer(season: 2, media_type: 'anime').call[:entry]

      expect(entry.subentries.order(:episode).first.source)
        .to eq('https://vidsrc.cc/v2/embed/anime/tt1355642/26/sub')
    end

    it 'starts at episode 1 for the first season' do
      entry = importer(media_type: 'anime').call[:entry]

      expect(entry.subentries.order(:episode).first.source)
        .to eq('https://vidsrc.cc/v2/embed/anime/tt1355642/1/sub')
    end
  end

  describe 'guard rails' do
    it 'reports a duplicate rather than adding the season twice' do
      importer.call

      expect { expect(importer.call[:status]).to eq(:duplicate) }.not_to change(Entry, :count)
    end

    it 'reports failure when TMDB is unreachable' do
      allow(tmdb).to receive(:fetch_season).and_raise(TmdbService::RequestError, 'timeout')

      expect {
        expect(importer.call[:status]).to eq(:failed)
      }.not_to change(Entry, :count)
    end

    it 'keeps the entry when one episode fails to save' do
      allow(Subentry).to receive(:create!).and_call_original
      allow(Subentry).to receive(:create!).with(hash_including(episode: 2)).and_raise(ActiveRecord::RecordInvalid.new(Subentry.new))

      result = importer.call

      expect(result[:status]).to eq(:created)
      expect(result[:episodes_added]).to eq(1)
      expect(result[:episodes_failed]).to eq([2])
    end
  end
end
