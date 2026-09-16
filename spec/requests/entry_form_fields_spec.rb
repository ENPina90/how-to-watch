require 'rails_helper'

# The entry forms were rearranged into rows, disclosures and a tabbed poster picker. The
# failure mode of a layout change is not that it looks wrong -- that you see -- but that a
# field goes missing in the move and quietly stops being editable, which nothing else here
# would catch. These list what each form must still ask for.
RSpec.describe 'What the entry forms ask for', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  def field_names(body) = body.scan(/name="entry\[(\w+)\]"/).flatten.uniq

  describe 'the edit form' do
    let(:entry) { create(:entry, list: list, media: 'movie') }

    it 'still carries every field it did before the rows and disclosures' do
      get edit_entry_path(entry), headers: { 'Accept' => 'text/plain' }

      expect(field_names(response.body)).to include(
        'name', 'list_id', 'media', 'position', 'length', 'source_url', 'plot', 'note',
        'provider_id', 'source_key', 'imdb', 'series', 'category',
        'pic', 'poster_url', 'poster'
      )
    end

    # Hidden behind <details> and behind a poster tab, which is a presentation choice: the
    # inputs are in the form either way, so a save does not blank what it did not show.
    it 'submits the fields it has tucked away rather than dropping them' do
      entry.update!(pic: 'https://example.test/keep.jpg', category: 'Westerns')

      patch entry_path(entry), params: { entry: { note: 'edited', pic: entry.pic, category: entry.category } }

      expect(entry.reload).to have_attributes(note: 'edited', pic: 'https://example.test/keep.jpg',
                                              category: 'Westerns')
    end

    it 'offers the episode fields on an episode' do
      episode = create(:entry, list: list, media: 'episode', name: 'S1E1', season: 1, episode: 1)

      get edit_entry_path(episode), headers: { 'Accept' => 'text/plain' }

      expect(field_names(response.body)).to include('season', 'episode')
    end
  end

  describe 'the custom-entry form' do
    it 'still carries every field it did before' do
      get new_list_entry_path(list)

      expect(field_names(response.body)).to include(
        'name', 'list_id', 'media', 'source_url', 'imdb', 'tmdb', 'year', 'length',
        'series', 'season', 'episode', 'category', 'genre', 'rating',
        'director', 'writer', 'actors', 'plot', 'note', 'review',
        'pic', 'poster_url', 'poster',
        'original', 'faneditor', 'fanedit_link', 'fanedit_type'
      )
    end
  end

  describe 'the poster picker' do
    it 'offers the three ways to give an entry a picture, on every form' do
      entry = create(:entry, list: list)

      get new_list_entry_path(list)
      expect(response.body).to include('From a link', 'Upload a file', 'Link only')

      get edit_entry_path(entry), headers: { 'Accept' => 'text/plain' }
      expect(response.body).to include('From a link', 'Upload a file', 'Link only')
    end
  end
end
