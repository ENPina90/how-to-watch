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
