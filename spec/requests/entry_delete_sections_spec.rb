require 'rails_helper'

# Deleting an entry leaves the page it was on wrong in two ways: the heading over its
# section still counts it, and a section it emptied is a heading over nothing with a filter
# that finds nothing. A delete is a plain link on the card, so unlike an add it says
# nothing about how the page is grouped -- the answer covers every grouping and Turbo drops
# whatever is not on the page.
RSpec.describe 'Deleting an entry from a section', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  def targets(action)
    response.body.scan(/<turbo-stream action="#{action}" target="([^"]+)"/).flatten
  end

  it 'counts one fewer where the section still has entries' do
    # Both in the seventies, so the section survives the delete and only its count moves.
    create(:entry, list: list, name: 'Alien', year: 1979, imdb: 'tt1', position: 1)
    doomed = create(:entry, list: list, name: 'Jaws', year: 1975, imdb: 'tt2', position: 2)

    delete entry_path(doomed), as: :turbo_stream

    expect(targets('replace')).to include('section-count-1970s')
    expect(response.body).to include('(1)')
    expect(targets('remove')).not_to include('section-1970s')
  end

  it 'takes the section and its filter away when it empties' do
    create(:entry, list: list, name: 'Alien', year: 1979, imdb: 'tt1', position: 1)
    doomed = create(:entry, list: list, name: 'Arrival', year: 2016, imdb: 'tt2', position: 2)

    delete entry_path(doomed), as: :turbo_stream

    expect(targets('remove')).to include('section-2010s', 'section-filter-2010s')
    expect(targets('remove')).not_to include('section-1970s')
  end

  it 'answers for every grouping, since the page never said which it is showing' do
    doomed = create(:entry, list: list, name: 'Alien', year: 1979, category: 'Horror', imdb: 'tt1', position: 1)

    delete entry_path(doomed), as: :turbo_stream

    # Its decade, its category and its media, all emptied by the same delete.
    expect(targets('remove')).to include('section-1970s', 'section-horror', 'section-movie')
  end

  it 'takes the row the order view wraps it in, not just the card' do
    doomed = create(:entry, list: list, name: 'Alien', imdb: 'tt1', position: 1)

    delete entry_path(doomed), as: :turbo_stream

    expect(targets('remove')).to include("entry_#{doomed.id}", "row-entry_#{doomed.id}")
  end

  it 'still corrects the channel count in the title' do
    create(:entry, list: list, name: 'Alien', imdb: 'tt1', position: 1)
    doomed = create(:entry, list: list, name: 'Aliens', imdb: 'tt2', position: 2)

    delete entry_path(doomed), as: :turbo_stream

    expect(targets('replace')).to include("header-count-#{list.id}")
  end
end
