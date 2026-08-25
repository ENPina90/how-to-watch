require 'rails_helper'

# season/episode used to be string columns, so every ordering needed
# CAST(NULLIF(col, '') AS INTEGER). Miss the cast anywhere and you get lexicographic
# order, where episode 10 sorts before episode 2. These pin the numeric behaviour.
RSpec.describe 'Subentry ordering' do
  let(:list) { create(:list) }
  let(:entry) { create(:entry, list: list, media: 'series') }

  def episode(season, number)
    Subentry.create!(entry: entry, season: season, episode: number, name: "S#{season}E#{number}")
  end

  it 'orders episodes numerically, not as text' do
    [12, 2, 1, 20, 3].each { |n| episode(1, n) }

    expect(entry.subentries.order(:season, :episode).pluck(:episode)).to eq([1, 2, 3, 12, 20])
  end

  it 'orders across seasons' do
    episode(2, 1)
    episode(10, 1)
    episode(1, 5)

    expect(entry.subentries.order(:season, :episode).pluck(:season)).to eq([1, 2, 10])
  end

  it 'stores numbers even when the form submits strings' do
    subentry = Subentry.create!(entry: entry, season: '3', episode: '07', name: 'From a form')

    expect(subentry.reload.season).to eq(3)
    expect(subentry.episode).to eq(7)
  end

  describe 'the user position walking episodes' do
    it 'advances past episode 9 in the right order' do
      user = create(:user)
      (8..11).each { |n| episode(1, n) }

      position = UserEntryPosition.find_or_create_for(user, entry)
      expect(position.current_subentry.episode).to eq(8)

      expect(position.advance_to_next!.episode).to eq(9)
      expect(position.advance_to_next!.episode).to eq(10)
      expect(position.go_to_previous!.episode).to eq(9)
    end
  end

  describe 'absolute numbering for anime' do
    it 'counts the episodes of earlier seasons' do
      (1..3).each { |n| episode(1, n) }
      later = episode(2, 4)

      expect(later.calculate_absolute_episode_number).to eq(7)
    end

    it 'returns the plain number for a first season' do
      expect(episode(1, 6).calculate_absolute_episode_number).to eq(6)
    end
  end
end

RSpec.describe 'Absolute episode numbering is only computed when needed' do
  let(:list) { create(:list) }
  let(:entry) { create(:entry, list: list, media: 'anime', imdb: 'tt1') }
  let!(:subentry) { Subentry.create!(entry: entry, season: 1, episode: 4, name: 'Ep') }

  it 'skips the COUNT when the template does not ask for it' do
    provider = Source.create!(name: 'Plain', kind: 'imdb',
                              templates: { 'anime' => 'https://p.test/%{series_imdb}/%{season}/%{episode}' })

    expect_any_instance_of(Subentry).not_to receive(:calculate_absolute_episode_number)

    expect(provider.url_for(entry, subentry: subentry)).to eq('https://p.test/tt1/1/4')
  end

  it 'computes it when the template uses it' do
    provider = Source.create!(name: 'Absolute', kind: 'imdb',
                              templates: { 'anime' => 'https://p.test/%{series_imdb}/%{absolute_episode}/sub' })

    expect(provider.url_for(entry, subentry: subentry)).to eq('https://p.test/tt1/4/sub')
  end
end
