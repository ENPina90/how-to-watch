require 'rails_helper'

# Adding from the search overlay while looking at the channel used to leave the page
# unchanged until a reload. The create endpoint already answered with a turbo stream, so
# the new card rides along in it.
RSpec.describe 'The card a new entry streams back', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Noir') }

  before { sign_in user }

  it 'gives the position view a container the card can be appended to' do
    create(:entry, list: list, name: 'Alien', position: 1)

    get list_path(list, criteria: 'Position')

    expect(response.body).to include('<div id="list-entries">')
  end

  # A grouped view has no end that a new entry belongs at -- it would have to be told which
  # section. Turbo drops a stream whose target is missing, so the append is simply inert.
  # Rendering a card from the controller is the part that can only be proven by doing it:
  # the partial reaches for current_user and the entry's attachments.
  describe 'the stream itself' do
    def appended(body)
      body[/<turbo-stream action="append" target="list-entries">.*?<\/turbo-stream>/m]
    end

    it 'carries the card for an entry' do
      entry = create(:entry, list: list, name: 'Alien', media: 'episode', season: 1, episode: 2)
      allow(OmdbApi).to receive(:get_movie).and_return({ 'Type' => 'movie', 'imdbID' => 'tt0078748' })
      allow(Entry).to receive(:create_from_source).and_return(entry)

      post list_entries_path(list), params: { imdb: 'tt0078748', tmdb: '348' }, as: :turbo_stream

      expect(appended(response.body)).to include('grid-card')
      expect(appended(response.body)).to include('Alien')
    end

    it 'carries it for an episode, which is created down a different branch' do
      entry = create(:entry, list: list, name: 'The Cage', media: 'episode', season: 1, episode: 1)
      importer = instance_double(EpisodeImporter, dom_key: 'S1E1',
                                                  call: { status: :created, message: 'added', entry: entry })
      allow(EpisodeImporter).to receive(:new).and_return(importer)

      post list_entries_path(list),
           params: { imdb: 'tt0059753', tmdb: '253', season: '1', episode: '1' },
           as: :turbo_stream

      expect(appended(response.body)).to include('The Cage')
    end
  end

  it 'labels each section of a grouped view so a card can be put in one' do
    create(:entry, list: list, name: 'Alien', year: 1979, position: 1)

    get list_path(list, criteria: 'Year')

    expect(response.body).not_to include('<div id="list-entries">')
    expect(response.body).to include('id="section-body-1970s"')
    expect(response.body).to include('id="section-count-1970s"')
    expect(response.body).to include('data-channel-criteria="Year"')
  end

  # Which container the card belongs in depends on how the page is grouped, so the browser
  # sends that along; the entry's own attributes decide which section of it.
  describe 'into a grouped view' do
    def appended_targets(body)
      body.scan(/<turbo-stream action="append" target="([^"]+)"/).flatten
    end

    before { allow(OmdbApi).to receive(:get_movie).and_return({ 'Type' => 'movie' }) }

    it 'lands in the decade it belongs to' do
      entry = create(:entry, list: list, name: 'Alien', year: 1979)
      allow(Entry).to receive(:create_from_source).and_return(entry)

      post list_entries_path(list), params: { imdb: 'tt0078748', criteria: 'Year' }, as: :turbo_stream

      expect(appended_targets(response.body)).to eq(['section-body-1970s'])
    end

    it 'lands in every genre it claims, the way the page files it under each' do
      entry = create(:entry, list: list, name: 'Alien', genre: 'Horror, Sci-Fi')
      allow(Entry).to receive(:create_from_source).and_return(entry)

      post list_entries_path(list), params: { imdb: 'tt0078748', criteria: 'Genre' }, as: :turbo_stream

      expect(appended_targets(response.body)).to eq(['section-body-horror', 'section-body-sci-fi'])
    end

    it 'corrects the heading count it just made wrong' do
      entry = create(:entry, list: list, name: 'Alien', category: 'Nostromo')
      allow(Entry).to receive(:create_from_source).and_return(entry)

      post list_entries_path(list), params: { imdb: 'tt0078748', criteria: 'Category' }, as: :turbo_stream

      expect(response.body).to include('target="section-count-nostromo"')
      expect(response.body).to include('(1)')
    end

    # The order view filters by category too, one card at a time, so a card streamed into
    # it needs the same wrapper the page gives the rest.
    it 'wraps the card the order view filters on' do
      entry = create(:entry, list: list, name: 'Alien', category: 'Nostromo')
      allow(Entry).to receive(:create_from_source).and_return(entry)
      allow(OmdbApi).to receive(:get_movie).and_return({ 'Type' => 'movie' })

      post list_entries_path(list), params: { imdb: 'tt0078748', criteria: 'Position' }, as: :turbo_stream

      expect(response.body).to include('data-section="Nostromo"')
      expect(response.body).to include('data-section-filter-target="section"')
    end

    it 'falls back to the ungrouped container when no grouping is sent' do
      entry = create(:entry, list: list, name: 'Alien', year: 1979)
      allow(Entry).to receive(:create_from_source).and_return(entry)

      post list_entries_path(list), params: { imdb: 'tt0078748' }, as: :turbo_stream

      expect(appended_targets(response.body)).to eq(['list-entries'])
    end
  end
end
