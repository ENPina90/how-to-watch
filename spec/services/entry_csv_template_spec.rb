require 'rails_helper'
require 'csv'

# The blank sheet the custom-entry page hands out. Its headers are the contract the importer
# reads back, so the two are checked against each other here rather than trusted to stay in
# step.
RSpec.describe EntryCsvTemplate do
  let(:user) { create(:user) }
  let(:westerns) { create(:list, user: user, name: 'Westerns') }
  let(:fanedits) { create(:list, user: user, name: 'Fanedits') }

  def table(lists) = CSV.parse(described_class.new(lists).generate, headers: true)

  it 'heads every column an entry can be typed into' do
    headers = table([westerns]).headers

    expect(headers).to start_with(*described_class::COLUMNS)
    expect(headers).to include('channel', 'name', 'media', 'imdb', 'source_url', 'length')
  end

  # CSV has one sheet and no data validation, so the choices cannot hang off the cells they
  # apply to. They ride along in their own columns instead.
  it 'lists the channels and media types it will accept' do
    rows = table([westerns, fanedits])

    expect(rows.map { |row| row['available_channels'] }.compact).to contain_exactly('Fanedits', 'Westerns')
    expect(rows.map { |row| row['available_media'] }.compact).to match_array(described_class::MEDIA)
  end

  it 'carries no entry data, only blank rows to type into' do
    rows = table([westerns])

    expect(rows.size).to be >= described_class::BLANK_ROWS
    expect(rows.map { |row| row.fields(*described_class::COLUMNS) }.flatten.compact).to be_empty
  end

  # A blank `channel` means the channel the file is uploaded to, so the template leaves it
  # empty rather than looking filled in when it is not.
  it 'leaves the channel column blank' do
    expect(table([westerns]).map { |row| row['channel'] }.compact).to be_empty
  end

  it 'names the file after the channel it was downloaded from' do
    expect(described_class.filename_for(westerns)).to eq('westerns-entries-template.csv')
  end

  # Only the values `entries/entry_#{media}` has a partial for: anything else is an entry
  # whose card cannot be drawn.
  it 'offers only media types the app can render' do
    described_class::MEDIA.each do |media|
      expect(Rails.root.join("app/views/entries/_entry_#{media}.html.erb")).to exist
    end
  end
end
