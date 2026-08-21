require 'rails_helper'

RSpec.describe 'Lists', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  describe 'GET /lists/:id grouping' do
    it 'groups by genre when some entries have no genre' do
      create(:entry, list: list, name: 'Has Genre', genre: 'Action, Sci-Fi')
      create(:entry, list: list, name: 'No Genre', genre: nil)

      get list_path(list, criteria: 'Genre')

      expect(response).to be_successful
      expect(response.body).to include('Action')
    end

    it 'groups by year when some entries have no year' do
      create(:entry, list: list, name: 'Dated', year: 1994)
      create(:entry, list: list, name: 'Undated', year: nil)

      get list_path(list, criteria: 'Year')

      expect(response).to be_successful
    end

    it 'groups by a numeric attribute without failing to sort the sections' do
      create(:entry, list: list, name: 'Rated', rating: 8.0)
      create(:entry, list: list, name: 'Unrated', rating: nil)

      get list_path(list, criteria: 'Rating')

      expect(response).to be_successful
    end

    it 'falls back to Position for a criteria that is not an offered grouping' do
      entry = create(:entry, list: list)

      expect {
        get list_path(list, criteria: 'destroy')
      }.not_to change(Entry, :count)

      expect(response).to be_successful
      expect(entry.reload).to be_persisted
    end
  end

  describe 'GET /lists/:id remembered view settings' do
    it 'keeps the saved grouping when the page is visited with no params' do
      list.update!(settings: 'Genre', sort: 'desc')
      create(:entry, list: list, genre: 'Action')

      get list_path(list)

      expect(list.reload.settings).to eq('Genre')
      expect(list.reload.sort).to eq('desc')
    end

    it 'persists an explicitly chosen grouping' do
      create(:entry, list: list, genre: 'Action')

      get list_path(list, criteria: 'Genre')

      expect(list.reload.settings).to eq('Genre')
    end
  end
end
