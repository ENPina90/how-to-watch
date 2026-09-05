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

  it 'still marks out the rating it does have' do
    entry = create(:entry, list: list, name: 'The Avengers', rating: 8.0)

    get entry_path(entry)

    expect(response.body).to include('*' * 8)
  end
end
