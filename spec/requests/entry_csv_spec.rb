require 'rails_helper'
require 'csv'

# The CSV round trip on the custom-entry page: download a blank sheet, fill it in, upload it.
RSpec.describe 'Entry CSV', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Fanedits') }

  before { sign_in user }

  def csv_upload(body)
    file = Tempfile.new(['entries', '.csv']).tap { |f| f.write(body); f.rewind }
    Rack::Test::UploadedFile.new(file.path, 'text/csv')
  end

  describe 'downloading the template' do
    it 'sends a CSV named after the channel' do
      get csv_template_list_entries_path(list)

      expect(response).to be_successful
      expect(response.media_type).to eq('text/csv')
      expect(response.headers['Content-Disposition']).to include('fanedits-entries-template.csv')
    end

    it 'lists the channels the member can file a row into' do
      create(:list, user: user, name: 'Westerns')

      get csv_template_list_entries_path(list)

      channels = CSV.parse(response.body, headers: true).map { |row| row['available_channels'] }.compact

      expect(channels).to include('Fanedits', 'Westerns')
    end
  end

  describe 'uploading a filled-in sheet' do
    it 'adds a row to the channel and says what it did' do
      post import_csv_list_entries_path(list), params: { file: csv_upload("name,media,length\nDespecialized,fanedit,125\n") }

      expect(response).to redirect_to(list_path(list))
      expect(flash[:notice]).to include('1 entry added')
      expect(list.entries.sole.name).to eq('Despecialized')
    end

    # A file of twenty rows where three were already there is a successful import the person
    # who uploaded it still needs to hear about.
    it 'reports the rows it could not take alongside the ones it did' do
      create(:entry, list: list, name: 'Despecialized', media: 'fanedit')

      post import_csv_list_entries_path(list), params: { file: csv_upload("name\nDespecialized\nHarmy's Revenge\n") }

      expect(flash[:notice]).to include('1 entry added')
      expect(flash[:alert]).to include('Despecialized')
    end

    it 'comes back to the form when nothing could be added' do
      post import_csv_list_entries_path(list), params: { file: csv_upload("name,media\n,movie\n") }

      expect(response).to redirect_to(new_list_entry_path(list))
      expect(flash[:alert]).to be_present
      expect(list.entries).to be_empty
    end

    # A spreadsheet writes as many rows as it has lines, so unlike the one-at-a-time create
    # it asks first whose channel it is filling.
    it 'refuses a channel the member cannot edit' do
      other = create(:list, user: create(:user))

      post import_csv_list_entries_path(other), params: { file: csv_upload("name\nAnything\n") }

      expect(other.entries).to be_empty
      expect(flash[:alert]).to include('cannot add')
    end
  end

  # CSRF tokens do not protect GET, so an import reachable over one would let a prefetch or an
  # <img src> write a spreadsheet's worth of rows.
  describe 'the verbs' do
    it 'does not import over GET' do
      get "/lists/#{list.id}/entries/import_csv"

      expect(response).to have_http_status(:not_found)
    end
  end
end
