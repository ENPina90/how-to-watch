require 'rails_helper'

# Grouping a channel by title: a section per opening letter, the way a shelf is arranged.
RSpec.describe 'Sorting a list by title', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before do
    sign_in user
    create(:entry, list: list, name: 'Zodiac', year: 2007, position: 1)
    create(:entry, list: list, name: 'Arrival', year: 2016, position: 2)
    create(:entry, list: list, name: 'Alien', year: 1979, position: 3)
  end

  def section_order
    response.body.scan(/<h3 id="([^"]+)">/).flatten
  end

  def entry_order
    response.body.scan(%r{<bold>(Zodiac|Arrival|Alien|1917|the Thing)</bold>}).flatten
  end

  it 'files each title under its opening letter' do
    get list_path(list, criteria: 'Title', sort: 'asc')

    expect(section_order).to eq(%w[A Z])
    expect(entry_order).to eq(['Alien', 'Arrival', 'Zodiac'])
  end

  it 'runs backwards on the second click' do
    get list_path(list, criteria: 'Title', sort: 'desc')

    expect(section_order).to eq(%w[Z A])
    expect(entry_order).to eq(['Zodiac', 'Arrival', 'Alien'])
  end

  # Ordering the sections alone would leave a letter's own titles in channel order, so
  # "A to Z" would only be true between letters.
  it 'sorts within a letter, not only between them' do
    get list_path(list, criteria: 'Title', sort: 'asc')

    expect(response.body.index('<bold>Alien</bold>')).to be < response.body.index('<bold>Arrival</bold>')
  end

  # One section each for "1917" and "2001" is a rail of sections holding one film apiece.
  it 'files everything that does not begin with a letter together' do
    create(:entry, list: list, name: '1917', year: 2019, position: 4)

    get list_path(list, criteria: 'Title', sort: 'asc')

    expect(section_order).to eq(%w[# A Z])
  end

  it 'files a lowercase title with its own letter' do
    create(:entry, list: list, name: 'the Thing', year: 1982, position: 4)

    get list_path(list, criteria: 'Title', sort: 'asc')

    expect(section_order).to eq(%w[A T Z])
  end

  # The rail filters what is on the page, so its buttons are the sections.
  it 'offers the letters as filters in the rail' do
    get list_path(list, criteria: 'Title', sort: 'asc')

    rail = response.body.scan(/data-section="([^"]+)"\s+data-section-filter-target="option"/).flatten
    expect(rail).to eq(%w[A Z])
  end

  it 'is offered in the menu, second after the channel\'s own order' do
    get list_path(list)

    menu = response.body[/<ul class="menu">.*?<\/ul>/m]
    expect(menu.scan(/criteria=(\w+)/).flatten.first(2)).to eq(%w[Position Title])
  end

  # criteria is whitelisted before it reaches the grouping, and Title has to be on the
  # list or it silently falls back to the channel's own order.
  it 'remembers the grouping on the channel' do
    get list_path(list, criteria: 'Title', sort: 'asc')

    expect(list.reload.settings).to eq('Title')
  end
end
