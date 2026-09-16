require 'rails_helper'

# The Details and Notes tabs on an entry card. They are fetched rather than rendered into
# the card, which is the whole point of them -- a channel page draws ~1,200 cards and
# `list_show_payload_spec.rb` holds each to a budget -- so the thing worth asserting is
# that the fetch exists, says only what it should, and that the note behind it is a write
# with a write's permissions.
RSpec.describe 'An entry card\'s tabs', type: :request do
  let(:owner) { create(:user) }
  let(:list) { create(:list, user: owner) }
  let(:entry) { create(:entry, list: list, media: 'movie', name: 'Stalker') }

  describe 'GET /entries/:id/panes' do
    before { sign_in owner }

    it 'lists what the card does not already show' do
      get panes_entry_path(entry)

      expect(response.body).to include('Director', 'Joss Whedon')
      expect(response.body).to include('Cast')
    end

    # The movie card already prints all four above the plot. Repeating them under a tab
    # makes a details panel that is mostly things you were already looking at.
    it 'leaves out what the card already shows' do
      get panes_entry_path(entry)

      details = response.body[/data-card-panes-pane="details".*?<\/div>/m]
      expect(details).not_to include('>Year<')
      expect(details).not_to include('>Runtime<')
      expect(details).not_to include('>Rating<')
      expect(details).not_to include('>Genre<')
    end

    # A fanedit card shows neither, so its pane is where they belong.
    it 'keeps a field for a media type whose card omits it' do
      fanedit = create(:entry, list: list, media: 'fanedit', name: 'A Cut', year: 1999, rating: 7.1)

      get panes_entry_path(fanedit)

      expect(response.body).to include('>Year<', '>Rating<')
    end

    it 'links the catalogues rather than printing the id' do
      get panes_entry_path(entry)

      expect(response.body).to include('https://www.imdb.com/title/tt0848228/')
    end

    it 'offers a box to write the note in' do
      get panes_entry_path(entry)

      expect(response.body).to include('<textarea')
      expect(response.body).to include('Some note')
    end

    it 'shows a subscriber the note without a box to change it' do
      sign_in create(:user)

      get panes_entry_path(entry)

      expect(response.body).not_to include('<textarea')
      expect(response.body).to include('Some note')
    end
  end

  describe 'PATCH /entries/:id/note' do
    it 'saves the note' do
      sign_in owner

      patch note_entry_path(entry), params: { entry: { note: 'Watch the long cut' } }

      expect(response).to have_http_status(:no_content)
      expect(entry.reload.note).to eq('Watch the long cut')
    end

    it 'clears the note when the box is emptied' do
      sign_in owner

      patch note_entry_path(entry), params: { entry: { note: '' } }

      expect(entry.reload.note).to eq('')
    end

    # The note is the channel's, not the reader's -- a column on the entry, which everybody
    # subscribed to the channel sees. Their own thoughts are the review, on UserEntry.
    it 'refuses somebody who may not edit the entry' do
      sign_in create(:user)

      patch note_entry_path(entry), params: { entry: { note: 'not mine to write' } }

      expect(entry.reload.note).to eq('Some note')
    end

    it 'refuses a signed-out visitor' do
      patch note_entry_path(entry), params: { entry: { note: 'stranger' } }

      expect(response).to redirect_to(new_user_session_path)
      expect(entry.reload.note).to eq('Some note')
    end
  end
end
