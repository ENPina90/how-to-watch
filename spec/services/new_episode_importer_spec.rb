# frozen_string_literal: true

require 'rails_helper'

# The whole difficulty is that TMDB lists episodes before they exist -- announced seasons,
# titled and summarised weeks ahead of broadcast. Most of these examples are about which
# episodes it is willing to believe.
RSpec.describe NewEpisodeImporter do
  let(:today) { Date.new(2026, 9, 14) }
  let(:list) { create(:list) }
  let(:show) do
    create(:entry, list: list, media: 'series', name: 'Rick and Morty', imdb: 'tt2861424',
                   tmdb: '60625', season: 9)
  end

  # season number => TMDB episode payloads
  let(:seasons) { {} }
  let(:last_aired) { [9, 2] }

  let(:tmdb) do
    instance_double(TmdbService).tap do |tmdb|
      allow(tmdb).to receive(:fetch_show) do
        {
          'last_episode_to_air' => last_aired && { 'season_number' => last_aired[0],
                                                   'episode_number' => last_aired[1] },
          'seasons' => seasons.keys.map { |number| { 'season_number' => number } }
        }
      end
      allow(tmdb).to receive(:fetch_season) { |_id, number| { 'episodes' => seasons.fetch(number) } }
      allow(tmdb).to receive(:fetch_show_external_ids).and_return('imdb_id' => 'tt2861424')
    end
  end

  def hold(entry, season, *numbers)
    numbers.each { |number| entry.subentries.create!(season: season, episode: number, name: "Held #{number}") }
  end

  def episode(number, aired, name: "The One With #{number}", runtime: 23)
    { 'episode_number' => number, 'air_date' => aired&.iso8601, 'name' => name, 'runtime' => runtime,
      'overview' => "Episode #{number} happens.", 'vote_average' => 7.5 }
  end

  def import(entry = show, &block)
    described_class.new(entry: entry, tmdb: tmdb, today: today).call(&block)
  end

  def added_numbers(result) = result.added.map { |subentry| [subentry.season, subentry.episode] }

  describe 'what counts as new' do
    it 'adds the aired episodes after the last one the entry holds' do
      hold(show, 9, 1)
      seasons[9] = [episode(1, today - 21), episode(2, today - 14)]

      result = import

      expect(added_numbers(result)).to eq([[9, 2]])
    end

    it 'copies what TMDB knows about the episode' do
      hold(show, 9, 1)
      seasons[9] = [episode(1, today - 21), episode(2, today - 14, name: 'Ricks Days', runtime: 24)]

      subentry = import.added.first

      expect(subentry).to have_attributes(name: 'Ricks Days', length: 24, plot: 'Episode 2 happens.',
                                          imdb: 'tt2861424', completed: false)
    end

    it 'does not fill a gap further back, which is a failed import rather than news' do
      hold(show, 9, 1, 3)
      last_aired.replace([9, 3])
      seasons[9] = [episode(1, today - 21), episode(2, today - 14), episode(3, today - 7)]

      expect(import.added).to be_empty
    end

    it 'carries a whole show on into a season it did not have' do
      hold(show, 8, 10)
      last_aired.replace([9, 1])
      seasons[8] = [episode(10, today - 400)]
      seasons[9] = [episode(1, today - 7)]

      expect(added_numbers(import)).to eq([[9, 1]])
    end

    it 'keeps a single-season entry to its own season' do
      season_entry = create(:entry, list: list, media: 'series', name: 'Rick and Morty - Season 8',
                                    series: 'Rick and Morty', imdb: 'tt2861424', tmdb: '60625', season: 8)
      hold(season_entry, 8, 9)
      last_aired.replace([9, 1])
      seasons[8] = [episode(9, today - 30), episode(10, today - 20)]
      seasons[9] = [episode(1, today - 7)]

      expect(added_numbers(import(season_entry))).to eq([[8, 10]])
      expect(tmdb).not_to have_received(:fetch_season).with('60625', 9)
    end

    it 'has nothing to say about an entry that holds no episodes at all' do
      expect(import.skipped).to be_present
      expect(tmdb).not_to have_received(:fetch_show)
    end
  end

  describe 'telling a released episode from a placeholder' do
    before { hold(show, 9, 1) }

    it 'does not take an episode on its own air date' do
      seasons[9] = [episode(1, today - 7), episode(2, today)]

      expect(import.added).to be_empty
    end

    it 'does not take an announced episode with a date to come' do
      last_aired.replace([9, 1])
      seasons[9] = [episode(1, today - 7), episode(2, today + 7)]

      expect(import.added).to be_empty
    end

    # TMDB's own statement of how far the show has got outranks a date on one episode,
    # which is the field most often wrong on a placeholder.
    it 'does not take an episode past the last one TMDB says has aired, whatever its date' do
      last_aired.replace([9, 1])
      seasons[9] = [episode(1, today - 7), episode(2, today - 1)]

      expect(import.added).to be_empty
    end

    it 'does not take an episode with no air date' do
      seasons[9] = [episode(1, today - 7), episode(2, nil)]

      expect(import.added).to be_empty
    end

    it 'takes nothing from a show TMDB says has not aired anything' do
      allow(tmdb).to receive(:fetch_show).and_return('last_episode_to_air' => nil, 'seasons' => [])

      expect(import.added).to be_empty
    end

    it 'holds back a recent episode still carrying a stand-in title' do
      seasons[9] = [episode(1, today - 7), episode(2, today - 3, name: 'Episode 2')]

      result = import

      expect(result.added).to be_empty
      expect(result.held_back).to eq(1)
    end

    it 'holds back a recent episode with no runtime yet' do
      seasons[9] = [episode(1, today - 7), episode(2, today - 3, runtime: nil)]

      expect(import.held_back).to eq(1)
    end

    # Adding episode 3 would leave episode 2 behind the last one held, where next week's
    # run would never look for it again.
    it 'does not add a later episode over the head of one it held back' do
      last_aired.replace([9, 3])
      seasons[9] = [episode(1, today - 14), episode(2, today - 5, name: 'Episode 2'), episode(3, today - 2)]

      expect(import.added).to be_empty
    end

    it 'takes an unfinished episode as it stands once it has had long enough' do
      seasons[9] = [episode(1, today - 30), episode(2, today - 15, name: 'Episode 2', runtime: nil)]

      expect(added_numbers(import)).to eq([[9, 2]])
    end
  end

  describe 'making sure it is the right show' do
    before do
      hold(show, 9, 1)
      seasons[9] = [episode(1, today - 21), episode(2, today - 14)]
    end

    it 'adds nothing when the TMDB id belongs to a different show' do
      allow(tmdb).to receive(:fetch_show_external_ids).and_return('imdb_id' => 'tt0000001')

      result = import

      expect(result.added).to be_empty
      expect(result.skipped).to include('TMDB id')
    end

    # Older shows often have no imdb id on TMDB. Treating that as "nothing says otherwise"
    # is how a documentary nearly took on a 1960 variety show's episodes.
    it 'adds nothing when TMDB has no imdb id and the imdb id leads to another show' do
      allow(tmdb).to receive(:fetch_show_external_ids).and_return('imdb_id' => nil)
      allow(tmdb).to receive(:find_by_imdb_id).with('tt2861424').and_return('tv_results' => [{ 'id' => 4971 }])

      expect(import.added).to be_empty
    end

    it 'goes ahead when TMDB has no imdb id but the imdb id leads back to the same show' do
      allow(tmdb).to receive(:fetch_show_external_ids).and_return('imdb_id' => nil)
      allow(tmdb).to receive(:find_by_imdb_id).with('tt2861424').and_return('tv_results' => [{ 'id' => 60_625 }])

      expect(added_numbers(import)).to eq([[9, 2]])
    end

    it 'finds the show by its imdb id when the entry has no TMDB id' do
      show.update_column(:tmdb, nil)
      allow(tmdb).to receive(:find_by_imdb_id).with('tt2861424').and_return('tv_results' => [{ 'id' => 60_625 }])

      expect(added_numbers(import)).to eq([[9, 2]])
      expect(tmdb).to have_received(:fetch_season).with('60625', 9)
    end
  end

  describe 'the block' do
    before do
      hold(show, 9, 1)
      last_aired.replace([9, 3])
      seasons[9] = [episode(1, today - 21), episode(2, today - 14), episode(3, today - 7)]
    end

    it 'is handed each episode as it is created' do
      seen = []

      import { |subentry, payload| seen << [subentry.episode, payload['name']] }

      expect(seen).to eq([[2, 'The One With 2'], [3, 'The One With 3']])
    end

    it 'takes the episodes back out with it if it fails' do
      expect { import { raise ActiveRecord::RecordInvalid } }.to raise_error(ActiveRecord::RecordInvalid)

      expect(show.subentries.count).to eq(1)
    end
  end
end
