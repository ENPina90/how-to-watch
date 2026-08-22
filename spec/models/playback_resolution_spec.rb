require 'rails_helper'

# New entries no longer store a source URL, so playback depends entirely on the provider
# templates. This is the guard for that: every media type the app creates must resolve to
# a playable URL with the legacy columns empty.
RSpec.describe 'Playback resolution without legacy columns' do
  let(:user) { create(:user) }

  let!(:provider) do
    Source.create!(
      name: 'Primary', kind: 'imdb', active: true, position: 1, autoplay_param: 'autoplay',
      templates: {
        'movie' => 'https://p.test/movie?imdb=%{imdb}',
        'series' => 'https://p.test/tv?imdb=%{series_imdb}&s=%{season}&e=%{episode}',
        'episode' => 'https://p.test/tv?imdb=%{series_imdb}&s=%{season}&e=%{episode}',
        'anime' => 'https://p.test/tv?imdb=%{series_imdb}&s=%{season}&e=%{episode}'
      }
    )
  end

  let(:list) { create(:list, user: user, provider: provider) }

  def bare_entry(**attrs)
    create(:entry, **{ list: list, source: nil, source_two: nil, preferred_source: nil }.merge(attrs))
  end

  it 'resolves a movie' do
    entry = bare_entry(media: 'movie', imdb: 'tt0848228')

    expect(entry.embed_url).to eq('https://p.test/movie?imdb=tt0848228&autoplay=0')
  end

  it 'resolves a standalone episode' do
    entry = bare_entry(media: 'episode', imdb: 'tt0903747', season: 2, episode: 5)

    expect(entry.embed_url).to eq('https://p.test/tv?imdb=tt0903747&s=2&e=5&autoplay=0')
  end

  it 'resolves a series from the current subentry' do
    entry = bare_entry(media: 'series', imdb: 'tt0903747')
    subentry = Subentry.create!(entry: entry, season: '3', episode: '7', name: 'Ep')

    expect(entry.embed_url(subentry: subentry)).to eq('https://p.test/tv?imdb=tt0903747&s=3&e=7&autoplay=0')
  end

  it 'resolves anime from the current subentry' do
    entry = bare_entry(media: 'anime', imdb: 'tt2560140')
    subentry = Subentry.create!(entry: entry, season: '1', episode: '4', name: 'Ep')

    expect(entry.embed_url(subentry: subentry)).to eq('https://p.test/tv?imdb=tt2560140&s=1&e=4&autoplay=0')
  end

  it 'resolves a direct entry from its own provider and key' do
    direct = Source.create!(name: 'Drive', kind: 'direct', active: true,
                            templates: { 'default' => 'https://drive.test/file/%{source_key}/preview' })
    entry = bare_entry(media: 'fanedit', imdb: nil, provider: direct, source_key: 'abc123')

    expect(entry.embed_url).to eq('https://drive.test/file/abc123/preview')
  end

  it 'passes autoplay through' do
    entry = bare_entry(media: 'movie', imdb: 'tt1')

    expect(entry.embed_url(autoplay: true)).to end_with('autoplay=1')
  end

  describe 'a whole imported season' do
    it 'plays every episode without a stored URL' do
      season_payload = {
        'episodes' => [{ 'episode_number' => 1, 'name' => 'One' }, { 'episode_number' => 2, 'name' => 'Two' }]
      }
      tmdb = instance_double(TmdbService, fetch_season: season_payload)

      entry = SeasonImporter.new(list: list, tmdb_id: '1396', series_imdb_id: 'tt0903747',
                                 series_name: 'Breaking Bad', season: 1, tmdb: tmdb).call[:entry]

      urls = entry.subentries.order(:episode).map { |sub| entry.embed_url(subentry: sub) }

      expect(urls).to eq([
        'https://p.test/tv?imdb=tt0903747&s=1&e=1&autoplay=0',
        'https://p.test/tv?imdb=tt0903747&s=1&e=2&autoplay=0'
      ])
    end
  end

  describe 'when no provider can build a URL' do
    it 'still falls back to a legacy source on an old entry' do
      Source.update_all(active: false)
      entry = create(:entry, list: list, media: 'movie', imdb: nil, source: 'https://legacy.test/old')

      expect(entry.embed_url).to eq('https://legacy.test/old?autoplay=0')
    end

    it 'reports nothing playable for a new entry with no legacy source' do
      Source.update_all(active: false)
      entry = bare_entry(media: 'movie', imdb: nil)

      expect(entry.embed_url).to be_blank
    end
  end
end
