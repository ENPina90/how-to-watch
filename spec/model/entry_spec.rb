require 'rails_helper'

RSpec.describe Entry, type: :model do
  let(:list) { create(:list) }
  let(:valid_entry_attributes) do
    {
      position: 1,
      franchise: 'Marvel',
      media: 'movie',
      season: nil,
      episode: nil,
      name: 'Avengers',
      category: 'Action',
      length: 120,
      year: 2012,
      plot: 'Earth\'s mightiest heroes must come together...',
      pic: 'some_url',
      source: 'https://v2.vidsrc.me/embed/tt0848228',
      genre: 'Action, Adventure, Sci-Fi',
      director: 'Joss Whedon',
      writer: 'Joss Whedon',
      actors: 'Robert Downey Jr., Chris Evans, Scarlett Johansson',
      rating: 8.0,
      language: 'English',
      note: 'Some note'
    }
  end
  let(:omdb_response) do
    file_path = Rails.root.join('spec/fixtures/omdb_response.json')
    JSON.parse(File.read(file_path))
  end

  describe '.create_from_source' do
    context 'with valid attributes' do
      it 'creates an entry successfully' do
        entry = Entry.create_from_source(omdb_response, list, true)
        expect(entry).to be_persisted
        expect(entry.name).to eq('The Avengers')
        expect(entry.completed).to be_truthy
      end
    end

    context 'with invalid attributes' do
      it 'logs an error and creates a FailedEntry' do
        allow(Entry).to receive(:create!).and_raise(StandardError.new('Some error'))
        expect(Rails.logger).to receive(:error).with(/Failed to create movie entry/)
        message = Entry.create_from_source(omdb_response, list, true)
        expect(message).to eq("Failed to create movie entry: Some error")
        expect(FailedEntry.where(name: 'The Avengers', year: 2012)).to exist
      end
    end
  end

  describe '.search_by_input' do
    it 'finds entries by name' do
      entry = create(:entry, list: list)
      results = Entry.search_by_input('Avengers')
      expect(results).to include(entry)
    end
  end

  describe '.to_csv' do
    it 'exports entries to CSV format' do
      create(:entry, list: list)
      csv_data = Entry.to_csv
      expect(csv_data).to include('Avengers')
    end
  end

  describe '.like' do
    it 'finds an entry with a similar name' do
      entry = create(:entry, list: list)
      result = Entry.like('Aveng')
      expect(result).to eq(entry)
    end
  end
end
