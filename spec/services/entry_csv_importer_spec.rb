require 'rails_helper'
require 'csv'

# Batch-adding entries from the sheet EntryCsvTemplate hands out. The two kinds of row -- one
# with an imdb id to look up, one with nothing but what was typed -- are the whole of it.
RSpec.describe EntryCsvImporter do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Fanedits') }

  # A StringIO stands in for the uploaded file: the importer only reads it.
  def upload(rows, headers: EntryCsvTemplate::COLUMNS)
    csv = CSV.generate do |csv|
      csv << headers
      rows.each { |row| csv << headers.map { |header| row[header] } }
    end

    StringIO.new(csv)
  end

  def import(rows, **options)
    described_class.new(file: upload(rows, **options.extract!(:headers)), list: list, user: user, **options).call
  end

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

  describe 'a row with nothing but what was typed' do
    it 'creates the entry it describes' do
      result = import([{ 'name' => 'Star Wars: Despecialized', 'media' => 'fanedit', 'length' => '125' }])

      expect(result.errors).to be_empty
      entry = list.entries.sole
      expect(entry.name).to eq('Star Wars: Despecialized')
      expect(entry.media).to eq('fanedit')
      expect(entry.length).to eq(125)
      expect(entry.position).to eq(1)
    end

    # What this page is for: a cut, a rip or a recording with no id behind it. Same default
    # the form beside it uses.
    it 'files a row with no media as a fanedit' do
      import([{ 'name' => 'Dad’s wedding video' }])

      expect(list.entries.sole.media).to eq('fanedit')
    end

    it 'refuses a row with no name and nothing to look one up from' do
      result = import([{ 'media' => 'movie', 'year' => '1982' }])

      expect(list.entries).to be_empty
      expect(result.errors.first).to include('a name is needed')
    end

    # A typo in one cell should not be why a row of real data is thrown away.
    it 'falls back to the default rather than saving media the app cannot draw' do
      import([{ 'name' => 'Something', 'media' => 'documentary' }])

      expect(list.entries.sole.media).to eq('fanedit')
    end
  end

  describe 'a row carrying an imdb id' do
    before { allow(OmdbApi).to receive(:get_movie).with('tt0083658').and_return(omdb_payload) }

    it 'has the rest looked up for it' do
      import([{ 'imdb' => 'tt0083658' }])

      entry = list.entries.sole
      expect(entry.name).to eq('Blade Runner')
      expect(entry.media).to eq('movie')
      expect(entry.year).to eq(1982)
      expect(entry.length).to eq(117)
      expect(entry.director).to eq('Ridley Scott')
    end

    # The point of typing a row by hand about a film the API already knows.
    it 'lets what was typed win over what the lookup said' do
      import([{ 'imdb' => 'tt0083658', 'name' => "Blade Runner: The Final Cut", 'length' => '117', 'note' => 'Ripped from the 4K' }])

      entry = list.entries.sole
      expect(entry.name).to eq('Blade Runner: The Final Cut')
      expect(entry.note).to eq('Ripped from the 4K')
      # Untouched cells still come from the lookup.
      expect(entry.director).to eq('Ridley Scott')
    end

    it 'keeps the row when the lookup finds nothing' do
      allow(OmdbApi).to receive(:get_movie).with('tt9999999').and_return(nil)

      import([{ 'imdb' => 'tt9999999', 'name' => 'Something unlisted' }])

      expect(list.entries.sole.name).to eq('Something unlisted')
    end
  end

  describe 'the channel column' do
    let(:westerns) { create(:list, user: user, name: 'Westerns') }

    it 'defaults to the channel the file was uploaded to' do
      import([{ 'name' => 'A' }])

      expect(list.entries.sole.name).to eq('A')
    end

    it 'files a row into another of the member’s channels when it names one' do
      westerns
      import([{ 'name' => 'A', 'channel' => 'westerns' }])

      expect(westerns.entries.sole.name).to eq('A')
      expect(list.entries).to be_empty
    end

    # Otherwise a sheet could write into somebody else's channel by typing its name.
    it 'refuses a channel that is not the member’s' do
      create(:list, user: create(:user), name: 'Somebody else’s')

      result = import([{ 'name' => 'A', 'channel' => 'Somebody else’s' }])

      expect(Entry.count).to eq(0)
      expect(result.errors.first).to include('no channel of yours')
    end
  end

  describe 'rows that are already there' do
    it 'skips a name the channel already holds instead of failing on it' do
      create(:entry, list: list, name: 'Already here', media: 'fanedit')

      result = import([{ 'name' => 'Already here' }, { 'name' => 'New one' }])

      expect(result.created.map(&:name)).to eq(['New one'])
      expect(result.skipped.first).to include('Already here')
      expect(result.errors).to be_empty
    end

    it 'skips an imdb id the channel already holds' do
      allow(OmdbApi).to receive(:get_movie).and_return(omdb_payload)
      create(:entry, list: list, imdb: 'tt0083658', name: 'Blade Runner', media: 'movie')

      result = import([{ 'imdb' => 'tt0083658' }])

      expect(result.created).to be_empty
      expect(result.skipped.size).to eq(1)
    end
  end

  describe 'the file itself' do
    # Every row of the blank template carries the reference columns and nothing else.
    it 'ignores the template’s blank rows' do
      file = StringIO.new(EntryCsvTemplate.new([list]).generate)

      result = described_class.new(file: file, list: list, user: user).call

      expect(result.created).to be_empty
      expect(result.errors).to be_empty
      expect(result.skipped).to be_empty
    end

    it 'ignores columns it does not know' do
      result = import([{ 'name' => 'A', 'available_channels' => 'Fanedits', 'nonsense' => 'x' }],
                      headers: EntryCsvTemplate::COLUMNS + %w[available_channels nonsense])

      expect(result.errors).to be_empty
      expect(list.entries.sole.name).to eq('A')
    end

    # Excel leaves one of these on the front of the first header, which would otherwise
    # become part of its name and leave `channel` unreadable.
    it 'reads a sheet exported with a byte-order mark' do
      file = StringIO.new("\xEF\xBB\xBFname,media\nA,movie\n")

      result = described_class.new(file: file, list: list, user: user).call

      expect(result.errors).to be_empty
      expect(list.entries.sole.name).to eq('A')
    end

    it 'says so when no file was chosen' do
      result = described_class.new(file: nil, list: list, user: user).call

      expect(result.errors.first).to include('No file')
    end

    it 'refuses a file that is not CSV' do
      result = described_class.new(file: StringIO.new("name\n\"unclosed"), list: list, user: user).call

      expect(result.errors.first).to include('could not be read')
    end

    # Each row with an id is an OMDB round trip, and the import runs inside the request.
    it 'refuses more rows than one upload can take' do
      rows = Array.new(described_class::MAX_ROWS + 1) { |i| { 'name' => "Film #{i}" } }

      result = import(rows)

      expect(Entry.count).to eq(0)
      expect(result.errors.first).to include("#{described_class::MAX_ROWS} is the most")
    end
  end

  describe 'what it reports' do
    it 'counts what happened to every row in one sentence' do
      create(:entry, list: list, name: 'Already here', media: 'fanedit')

      result = import([{ 'name' => 'Already here' }, { 'name' => 'New one' }, { 'year' => '1982' }])

      expect(result.summary).to eq('1 entry added, 1 skipped, 1 row failed')
      expect(result).to be_any_problems
    end
  end
end
