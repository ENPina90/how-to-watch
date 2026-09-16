require 'rails_helper'

# "+ Details" on a search result opens the custom-entry form filled in from the API. What
# makes it different from the + button beside it is that nothing has been created: the form
# is a form until Create Entry is pressed.
RSpec.describe 'The prefilled custom-entry form', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  let(:omdb_payload) do
    {
      'Type' => 'movie',
      'Title' => 'Blade Runner',
      'imdbID' => 'tt0083658',
      'Year' => '1982',
      'Poster' => 'https://example.test/blade.jpg',
      'Genre' => 'Sci-Fi',
      'Director' => 'Ridley Scott',
      'Writer' => 'Hampton Fancher',
      'Actors' => 'Harrison Ford',
      'Plot' => 'A blade runner must pursue six replicants.',
      'Runtime' => '117 min',
      'imdbRating' => '8.1',
      'Language' => 'English'
    }
  end

  before { sign_in user }

  it 'fills the fields in without creating an entry' do
    allow(OmdbApi).to receive(:get_movie).with('tt0083658').and_return(omdb_payload)

    expect { get new_list_entry_path(list, imdb: 'tt0083658', tmdb: '78') }.not_to change(Entry, :count)

    expect(response.body).to include('value="Blade Runner"')
    expect(response.body).to include('value="tt0083658"')
    expect(response.body).to include('value="https://example.test/blade.jpg"')
    expect(response.body).to include('<option selected="selected" value="movie">Movie</option>')
  end

  it 'still draws the form when the lookup finds nothing' do
    allow(OmdbApi).to receive(:get_movie).and_return(nil)

    get new_list_entry_path(list, imdb: 'tt0000000')

    expect(response).to be_successful
    expect(response.body).to include('name="entry[name]"')
  end

  it 'draws a blank form when no id was passed' do
    expect(OmdbApi).not_to receive(:get_movie)

    get new_list_entry_path(list)

    expect(response).to be_successful
  end

  # Duplicate on an entry card. It used to POST a copy into the member's first channel from
  # inside the card's turbo frame, where the redirect never drew; now it opens this form
  # filled in from the entry, and nothing exists until Create Entry.
  describe 'duplicating an entry', :needs_provider do
    let(:original) do
      create(:entry, list: list, name: 'Star Wars: Despecialized', media: 'fanedit',
                     imdb: 'tt0076759', year: 1977, length: 121, director: 'George Lucas')
    end

    it 'fills the fields in from the entry without creating one' do
      original

      expect { get new_list_entry_path(list, duplicate: original.id) }.not_to change(Entry, :count)

      expect(response.body).to include('value="Star Wars: Despecialized"')
      expect(response.body).to include('value="tt0076759"')
      expect(response.body).to include('value="George Lucas"')
      expect(response.body).to include('<option selected="selected" value="fanedit">Fanedit</option>')
      expect(response.body).to include('A copy of <strong>Star Wars: Despecialized</strong>')
    end

    # The form has no inputs for these, and a copy without its provider plays differently
    # from the entry it was copied from, or not at all.
    it 'carries what the form has no field for' do
      original.update!(series_imdb: 'tt0120915', source_key: 'abc123', provider_id: playable_provider.id)

      get new_list_entry_path(list, duplicate: original.id)

      expect(response.body).to include('name="entry[series_imdb]"')
      expect(response.body).to include('value="tt0120915"')
      expect(response.body).to include('name="entry[source_key]"')
      expect(response.body).to include('name="entry[provider_id]"')
    end

    it 'draws the blank form for an entry that has gone' do
      get new_list_entry_path(list, duplicate: 0)

      expect(response).to be_successful
      expect(response.body).not_to include('A copy of')
    end

    # Every card sits in a turbo frame of its own, so the link has to leave it.
    it 'is what the + on a card opens' do
      original

      get list_path(list)

      expect(response.body).to include(%(href="#{new_list_entry_path(list, duplicate: original.id)}"))
      expect(response.body).to include('title="Duplicate"')
      expect(response.body).to include('data-turbo-frame="_top"')
      expect(response.body).not_to include('/duplicate')
    end
  end

  describe 'creating what the form was filled with' do
    it 'saves the entry and goes to the channel' do
      post list_entries_path(list), params: {
        custom: true,
        entry: { name: 'Blade Runner: Final Cut', media: 'movie', length: '117', list_id: list.id }
      }

      expect(response).to redirect_to(list_path(list))
      expect(list.entries.sole.name).to eq('Blade Runner: Final Cut')
    end

    # The dropdown was being read and then overwritten with the channel the form was opened
    # from, so choosing another one in it did nothing.
    it 'honours the channel the dropdown named' do
      other = create(:list, user: user)

      post list_entries_path(list), params: {
        custom: true, entry: { name: 'Filed elsewhere', media: 'fanedit', list_id: other.id }
      }

      expect(other.entries.sole.name).to eq('Filed elsewhere')
      expect(list.entries).to be_empty
      expect(response).to redirect_to(list_path(other))
    end

    # An id from elsewhere must not be a way to write into a channel the dropdown never
    # offered.
    it 'ignores a channel that is not the member’s' do
      stranger = create(:list, user: create(:user))

      post list_entries_path(list), params: {
        custom: true, entry: { name: 'Stays put', media: 'fanedit', list_id: stranger.id }
      }

      expect(stranger.entries).to be_empty
      expect(list.entries.sole.name).to eq('Stays put')
    end

    it 'redraws the form with the reason when the entry will not save' do
      post list_entries_path(list), params: { custom: true, entry: { name: '', media: 'fanedit' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to include("Name can't be blank")
    end

    # Downloaded and kept, the way the edit form and the change-poster modal do it -- and not
    # allowed to take the rest of the row down with it.
    it 'fetches a poster from a link after the entry has saved' do
      image = instance_double(RemoteImage::Result, ok?: true, io: StringIO.new('jpeg'), content_type: 'image/jpeg', error: nil)
      allow(RemoteImage).to receive(:fetch).and_return(image)

      post list_entries_path(list), params: {
        custom: true,
        entry: { name: 'With a poster', media: 'fanedit', poster_url: 'https://example.test/p.jpg' }
      }

      expect(list.entries.sole.poster).to be_attached
    end

    # The duplicate form opens with the original's poster already in the fetch field, so a
    # copy keeps a picture when nothing else is offered. It was beating an actual upload:
    # the fetch runs after the save, so the uploaded file was attached and then replaced by
    # the original's poster, and a duplicate could not be given a picture of its own.
    it 'keeps an uploaded poster rather than fetching the link the duplicate form prefilled' do
      expect(RemoteImage).not_to receive(:fetch)

      post list_entries_path(list), params: {
        custom: true,
        entry: {
          name: 'A copy', media: 'fanedit',
          poster: Rack::Test::UploadedFile.new(Rails.root.join('app/assets/images/please_stand_by.png'), 'image/png'),
          poster_url: 'https://example.test/the-original.jpg'
        }
      }

      expect(list.entries.sole.poster).to be_attached
    end

    it 'keeps the entry when the poster link turns out to be bad' do
      image = instance_double(RemoteImage::Result, ok?: false, error: 'not an image')
      allow(RemoteImage).to receive(:fetch).and_return(image)

      post list_entries_path(list), params: {
        custom: true,
        entry: { name: 'Poster failed', media: 'fanedit', poster_url: 'https://example.test/nope' }
      }

      expect(list.entries.sole.name).to eq('Poster failed')
      expect(flash[:alert]).to include('not an image')
    end
  end
end
