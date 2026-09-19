# frozen_string_literal: true

require 'rails_helper'

# A programme with no runtime is kept off the cable schedule, so every blank one is missing
# from the dial. TMDB knows most of them; this is the part of the weekly sweep that asks.
RSpec.describe RuntimeBackfill do
  let(:list) { create(:list) }

  let(:tmdb) do
    instance_double(TmdbService).tap do |tmdb|
      allow(tmdb).to receive(:find_by_imdb_id) do |imdb|
        {
          'tt0185906' => { 'tv_results' => [{ 'id' => 4613 }] },
          'tt0172495' => { 'movie_results' => [{ 'id' => 98 }] }
        }.fetch(imdb, {})
      end
      allow(tmdb).to receive(:fetch_season) do |_show, season|
        raise TmdbService::RequestError, 'no such season' unless season.to_i == 1

        { 'episodes' => [{ 'episode_number' => 1, 'runtime' => 74 },
                         { 'episode_number' => 2, 'runtime' => 52 },
                         { 'episode_number' => 3, 'runtime' => nil }] }
      end
      allow(tmdb).to receive(:fetch_movie).with(98).and_return('runtime' => 155)
      allow(tmdb).to receive(:fetch_episode).with(4613, 1, 3).and_return('runtime' => 66)
    end
  end

  def backfill = described_class.call(tmdb: tmdb)

  describe 'a series' do
    let(:show) do
      create(:entry, list: list, media: 'series', name: 'Band of Brothers', imdb: 'tt0185906',
                     tmdb: nil, length: 594)
    end

    it 'fills each bare episode from its season' do
      pilot = show.subentries.create!(season: 1, episode: 1, name: 'Currahee', length: nil)
      second = show.subentries.create!(season: 1, episode: 2, name: 'Day of Days', length: 0)

      backfill

      expect(pilot.reload.length).to eq(74)
      expect(second.reload.length).to eq(52)
    end

    it 'leaves a runtime somebody set alone' do
      set = show.subentries.create!(season: 1, episode: 1, name: 'Currahee', length: 70)

      backfill

      expect(set.reload.length).to eq(70)
    end

    # A show's own figure is the whole series, and nothing reads it any more.
    it 'does not touch the show itself' do
      show.subentries.create!(season: 1, episode: 1, name: 'Currahee', length: nil)

      backfill

      expect(show.reload.length).to eq(594)
    end

    it 'counts what TMDB had no figure for as unanswered' do
      show.subentries.create!(season: 1, episode: 3, name: 'Carentan', length: nil)
      show.subentries.create!(season: 2, episode: 1, name: 'Nowhere', length: nil)

      result = backfill

      expect(result.checked).to eq(2)
      expect(result.filled).to eq(0)
      expect(result.unanswered).to eq(2)
    end

    it 'uses the TMDB id already on the show rather than looking it up' do
      show.update!(tmdb: '4613')
      show.subentries.create!(season: 1, episode: 1, name: 'Currahee', length: nil)

      backfill

      expect(tmdb).not_to have_received(:find_by_imdb_id)
    end
  end

  it 'fills a film by its imdb id' do
    film = create(:entry, list: list, media: 'movie', imdb: 'tt0172495', length: nil)

    backfill

    expect(film.reload.length).to eq(155)
  end

  it 'fills a standalone episode through its show' do
    episode = create(:entry, list: list, media: 'episode', imdb: 'tt0000003', series_imdb: 'tt0185906',
                             season: 1, episode: 3, length: nil)

    backfill

    expect(episode.reload.length).to eq(66)
  end

  # Oats Studios' shorts carry the imdb id of the volume they came out in, and a lookup by
  # it would hand every one of them the volume's runtime.
  it 'does not look up a standalone episode with no show to find it under' do
    episode = create(:entry, list: list, media: 'episode', imdb: 'tt0172495', series_imdb: nil,
                             season: nil, episode: nil, length: nil)

    backfill

    expect(episode.reload.length).to be_nil
  end

  # A fanedit runs as long as the editor made it, and TMDB's figure is the source film's.
  it 'leaves fanedits alone' do
    fanedit = create(:entry, list: list, media: 'fanedit', imdb: 'tt0172495', length: nil)

    backfill

    expect(fanedit.reload.length).to be_nil
  end

  # Below MIN_MINUTES the schedule treats a runtime as missing, so this does too.
  it 'replaces a runtime too short to be real' do
    film = create(:entry, list: list, media: 'movie', imdb: 'tt0172495', length: 2)

    backfill

    expect(film.reload.length).to eq(155)
  end

  it 'carries on past a title TMDB will not answer for' do
    allow(tmdb).to receive(:find_by_imdb_id).with('tt9999999').and_raise(TmdbService::RequestError, 'timeout')
    create(:entry, list: list, name: 'Unknown', media: 'movie', imdb: 'tt9999999', length: nil, position: 1)
    film = create(:entry, list: list, media: 'movie', imdb: 'tt0172495', length: nil, position: 2)

    backfill

    expect(film.reload.length).to eq(155)
  end
end
