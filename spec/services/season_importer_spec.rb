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

  let(:show_payload) do
    { 'seasons' => [{ 'season_number' => 0, 'episode_count' => 3 },
                    { 'season_number' => 1, 'episode_count' => 25 },
                    { 'season_number' => 2, 'episode_count' => 12 }] }
  end

  let(:tmdb) { instance_double(TmdbService, fetch_season: season_payload, fetch_show: show_payload) }

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

    it 'stores the series imdb id on each subentry' do
      entry = importer.call[:entry]

      expect(entry.subentries.pluck(:imdb).uniq).to eq(['tt1355642'])
    end

    it 'makes a single TMDB request for a series season' do
      importer.call

      expect(tmdb).to have_received(:fetch_season).once
      expect(tmdb).not_to have_received(:fetch_show)
    end
  end

  describe 'an anime season' do
    it 'imports with a single TMDB call, like a series' do
      # Absolute numbering used to be baked into the stored URL, which cost a second call
      # for the preceding seasons' episode counts. The live providers key anime off
      # season/episode, so neither the URL nor the offset is computed at import time.
      result = importer(season: 2, media_type: 'anime').call

      expect(result[:status]).to eq(:created)
      expect(tmdb).to have_received(:fetch_season).once
      expect(tmdb).not_to have_received(:fetch_show)
    end

    it 'records the media type on the parent entry' do
      expect(importer(media_type: 'anime').call[:entry].media).to eq('anime')
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
