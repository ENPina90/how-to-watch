require 'rails_helper'

# The row above the entries: subscribe at one end, adding and finding at the other, and the
# search collapsed to its icon until someone wants it.
RSpec.describe 'The channel action row', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:owner) { create(:user) }
  let(:list) { create(:list, user: owner, name: 'Noir') }

  before do
    sign_in user
    create(:entry, list: list, position: 1)
  end

  def row
    response.body[/<div class="list-input">.*?<ul class="menu">/m]
  end

  # Subscribing and adding are on the left; what you do to the channel itself is on the
  # right, out of the way of the search as it grows.
  it 'groups subscribe, add and search on the left, ahead of the channel controls' do
    get list_path(list)

    expect(row.index('subscription-pill')).to be < row.index('expanding-search')
    expect(row.index('expanding-search')).to be < row.index('list-options')
  end

  it 'adds an entry with an icon, between subscribe and the search' do
    get list_path(list)

    expect(row).to include('fa-circle-plus')
    expect(row.index('subscription-pill')).to be < row.index('fa-circle-plus')
    expect(row.index('fa-circle-plus')).to be < row.index('fa-magnifying-glass')
    expect(row).not_to include('+ Entry')
  end

  it 'keeps the search a real GET form, only collapsed' do
    get list_path(list)

    expect(row).to include('data-controller="expanding-search"')
    expect(row).to include('click->expanding-search#open')
    expect(row).to include('name="query"')
    # It searches the channel it is on; the navbar's searches everything.
    expect(row).to include('placeholder="Search this channel"')
  end

  # The subscribe/unsubscribe turbo stream replaces this id, so it has to survive the
  # restyle.
  it 'keeps the id the subscribe stream replaces' do
    get list_path(list)

    expect(response.body).to include(%(id="subscription-#{list.id}"))
  end

  it 'marks the subscribed state, which is what the colour keys off' do
    user.subscribe_to!(list)

    get list_path(list)

    expect(row).to include('subscription-pill--subscribed')
    expect(row).to include('Subscribed')
  end
end
