# frozen_string_literal: true

require 'rails_helper'

# An entry opened on its own, rather than as a card in a channel. Bulk-imported episodes
# arrive with most of their optional fields empty, and this page renders them unguarded --
# a nil rating used to take the whole page down with a TypeError from String#*.
RSpec.describe 'Entry page' do
  let(:user) { create(:user) }
  let(:list) { create(:list) }

  before { sign_in user }

  it 'renders an entry that has no rating' do
    entry = create(:entry, list: list, name: 'Piccolo vs Android 17', rating: nil)

    get entry_path(entry)

    expect(response).to be_successful
  end

  it 'renders an entry with none of its optional fields filled in' do
    entry = create(:entry, list: list, name: 'Episode #1.3', rating: nil, plot: nil,
                           genre: nil, year: nil, imdb: nil, note: nil)

    get entry_path(entry)

    expect(response).to be_successful
    expect(response.body).to include('Episode #1.3')
  end

  it 'shows the rating it does have' do
    entry = create(:entry, list: list, name: 'The Avengers', rating: 8.0)

    get entry_path(entry)

    expect(response.body).to include('8.0')
  end

  # The same card a channel renders, so an entry opened on its own is not a poorer version
  # of itself: the controls that are there in a list are there here.
  it 'carries the channel card, with its modals and the controller that drives them' do
    entry = create(:entry, list: list, name: 'The Avengers', trailer: 'https://youtu.be/abc')

    get entry_path(entry)

    expect(response.body).to include('data-controller="edit"')
    expect(response.body).to include('editModal', 'reviewModal', 'trailerModal', 'posterModal')
  end

  # Reachable signed out on a public channel once the site is open, and the card has to
  # cope: no watched control, no edit pen, no Letterboxd score to look up.
  it 'renders for a signed-out visitor when the site is open' do
    entry = create(:entry, list: list, name: 'The Avengers')
    AppSetting.update_access_mode!('open')
    sign_out user

    get entry_path(entry)

    expect(response).to be_successful
    expect(response.body).not_to include('Change poster')
  end

  it 'renders an episode, which uses a different card' do
    entry = create(:entry, list: list, name: 'Episode #1.3', media: 'episode', season: 1, episode: 3)

    get entry_path(entry)

    expect(response).to be_successful
    expect(response.body).to include('Episode #1.3')
  end
end
