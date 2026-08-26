require 'rails_helper'

# Clicking the grouping that is already active flips the direction rather than re-running
# the same ascending sort. `lists.sort` holds that direction; it used to hold whatever the
# criteria dropdown wrote there, and its mere presence meant "descending".
RSpec.describe 'Sorting a list', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before do
    sign_in user
    create(:entry, list: list, name: 'Arrival', year: 2016, position: 1)
    create(:entry, list: list, name: 'Alien', year: 1979, position: 2)
  end

  def section_order
    response.body.scan(/<h3 id="(\d{4}s)">/).flatten
  end

  def entry_order
    response.body.scan(%r{<bold>(Arrival|Aliens|Alien)</bold>}).flatten
  end

  it 'runs ascending on the first click' do
    get list_path(list, criteria: 'Year', sort: 'asc')

    expect(section_order).to eq(%w[1970s 2010s])
    expect(entry_order).to eq(%w[Alien Arrival])
  end

  it 'runs descending on the second' do
    get list_path(list, criteria: 'Year', sort: 'desc')

    expect(section_order).to eq(%w[2010s 1970s])
    expect(entry_order).to eq(%w[Arrival Alien])
  end

  it 'sorts within a section, not just between them' do
    create(:entry, list: list, name: 'Aliens', year: 1986, position: 3)

    get list_path(list, criteria: 'Year', sort: 'desc')

    expect(response.body.index('<bold>Aliens</bold>')).to be < response.body.index('<bold>Alien</bold>')
  end

  it 'points the active link at the opposite direction' do
    get list_path(list, criteria: 'Year', sort: 'asc')

    expect(response.body).to include(CGI.escapeHTML(list_path(list, criteria: 'Year', sort: 'desc')))
    expect(response.body).to include('fa-caret-up')
  end

  it 'starts other groupings ascending' do
    get list_path(list, criteria: 'Year', sort: 'desc')

    expect(response.body).to include(CGI.escapeHTML(list_path(list, criteria: 'Genre', sort: 'asc')))
  end

  it 'remembers the direction on a plain visit' do
    get list_path(list, criteria: 'Year', sort: 'desc')
    get list_path(list)

    expect(section_order).to eq(%w[2010s 1970s])
  end

  it 'keeps the remembered grouping when only a direction is given' do
    get list_path(list, criteria: 'Year', sort: 'asc')
    get list_path(list, sort: 'desc')

    expect(list.reload.settings).to eq('Year')
    expect(section_order).to eq(%w[2010s 1970s])
  end

  it 'ignores a direction it does not recognise' do
    get list_path(list, criteria: 'Year', sort: 'Genre')

    expect(section_order).to eq(%w[1970s 2010s])
  end

  describe 'grouping by date added' do
    before do
      list.entries.find_by(name: 'Alien').update_column(:created_at, Time.zone.parse('2024-12-02'))
      list.entries.find_by(name: 'Arrival').update_column(:created_at, Time.zone.parse('2025-08-14'))
    end

    def month_order
      response.body.scan(/<h3 id="([A-Z][a-z]+ \d{4})">/).flatten
    end

    it 'groups into months, oldest first' do
      get list_path(list, criteria: 'Added', sort: 'asc')

      expect(month_order).to eq(['December 2024', 'August 2025'])
      expect(entry_order).to eq(%w[Alien Arrival])
    end

    it 'reverses on the second click, months and entries alike' do
      create(:entry, list: list, name: 'Aliens', year: 1986, position: 3).update_column(:created_at, Time.zone.parse('2024-12-20'))

      get list_path(list, criteria: 'Added', sort: 'desc')

      expect(month_order).to eq(['August 2025', 'December 2024'])
      expect(entry_order).to eq(%w[Arrival Aliens Alien])
    end
  end

  it 'still renders the position view when a direction is remembered' do
    get list_path(list, criteria: 'Year', sort: 'desc')
    get list_path(list, criteria: 'Position')

    expect(section_order).to be_empty
    expect(entry_order).to eq(%w[Arrival Alien])
  end
end
