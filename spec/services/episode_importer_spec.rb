require 'rails_helper'

RSpec.describe EpisodeImporter do
  let(:list) { create(:list) }

  let(:show_payload) { { 'name' => 'Severance' } }
  let(:episode_payload) do
    {
      'name' => 'Good News About Hell',
      'overview' => 'Mark is promoted.',
      'still_path' => '/still.jpg',
      'vote_average' => 8.1,
      'air_date' => '2022-02-18',
      'runtime' => 57
    }
  end

  def importer(**overrides)
    described_class.new(**{ list: list, tmdb_id: '95396', season: 1, episode: 1, tmdb: tmdb }.merge(overrides))
  end

  let(:tmdb) do
    instance_double(TmdbService,
                    fetch_show: show_payload,
                    fetch_episode: episode_payload,
                    fetch_show_external_ids: { 'imdb_id' => 'tt11280740' })
  end

  describe 'creating an episode' do
    it 'builds the entry from the TMDB payloads' do
      result = importer.call

      expect(result[:status]).to eq(:created)
      entry = result[:entry]
      expect(entry.name).to eq('Severance - Good News About Hell')
      expect(entry.series).to eq('Severance')
      expect(entry.media).to eq('episode')
      expect(entry.season).to eq(1)
      expect(entry.episode).to eq(1)
      expect(entry.year).to eq(2022)
      expect(entry.length).to eq(57)
      expect(entry.pic).to eq('https://image.tmdb.org/t/p/w500/still.jpg')
      expect(entry.imdb).to eq('tt11280740')
    end

    it 'appends to the end of the list' do
      create(:entry, list: list, position: 7)

      expect(importer.call[:entry].position).to eq(8)
    end

    it 'prefers a supplied imdb id over a TMDB lookup' do
      result = importer(imdb_id: 'tt9999999').call

      expect(result[:entry].imdb).to eq('tt9999999')
      expect(tmdb).not_to have_received(:fetch_show_external_ids)
    end

    it 'falls back to a tmdb-derived id when TMDB has no imdb id' do
      allow(tmdb).to receive(:fetch_show_external_ids).and_return({ 'imdb_id' => nil })

      expect(importer.call[:entry].imdb).to eq('tmdb95396')
    end

    it 'survives the external id lookup failing' do
      allow(tmdb).to receive(:fetch_show_external_ids).and_raise(TmdbService::RequestError, 'boom')

      result = importer.call

      expect(result[:status]).to eq(:created)
      expect(result[:entry].imdb).to eq('tmdb95396')
    end
  end

  describe 'when the episode is already in the list' do
    it 'reports a duplicate and returns the existing entry' do
      existing = create(:entry, list: list, media: 'episode', imdb: 'tt11280740',
                                season: 1, episode: 1, name: 'Already here')

      result = importer.call

      expect(result[:status]).to eq(:duplicate)
      expect(result[:entry]).to eq(existing)
    end

    it 'matches on tmdb id when there is no imdb id to match on' do
      allow(tmdb).to receive(:fetch_show_external_ids).and_return({ 'imdb_id' => nil })
      existing = create(:entry, list: list, media: 'episode', tmdb: '95396',
                                season: 1, episode: 1, name: 'Already here')

      expect(importer.call[:entry]).to eq(existing)
    end
  end

  describe 'when TMDB is unreachable' do
    it 'reports the failure instead of raising' do
      allow(tmdb).to receive(:fetch_show).and_raise(TmdbService::RequestError, 'TMDB tv/95396 failed')

      expect {
        result = importer.call
        expect(result[:status]).to eq(:failed)
        expect(result[:message]).to include('Failed to add episode')
      }.not_to change(Entry, :count)
    end
  end

  describe '#dom_key' do
    it 'addresses the list page button for this episode' do
      expect(importer(season: 2, episode: 5).dom_key).to eq('S2E5')
    end
  end
end
