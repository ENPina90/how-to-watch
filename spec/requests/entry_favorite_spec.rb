require 'rails_helper'

# Filing a film in the member's own favourites channel. An entry belongs to one channel, so
# this is a copy rather than a move: the film stays on the channel that was playing it.
RSpec.describe 'Adding an entry to favourites', type: :request do
  let(:user) { create(:user) }
  let(:channel) { create(:list, user: user, name: 'Channel One') }
  let(:favourites) { create(:list, user: user, name: 'My Favourites') }
  let(:entry) do
    create(:entry, list: channel, name: 'The Death of Harvey', media: 'movie',
                   imdb: 'tt0000001', position: 1)
  end

  before { user.update!(favorite_list: favourites) }

  it 'files a copy in the favourites channel and leaves the original where it was' do
    sign_in user

    expect { post favorite_entry_path(entry) }
      .to change { favourites.entries.count }.by(1)

    expect(response).to have_http_status(:success)
    expect(entry.reload.list).to eq(channel)
    expect(favourites.entries.last.name).to eq('The Death of Harvey')
    expect(favourites.entries.last.imdb).to eq('tt0000001')
  end

  it 'answers with the copy, so the page can fill the heart' do
    sign_in user
    post favorite_entry_path(entry)

    body = response.parsed_body
    expect(body['favorited']).to be(true)
    expect(body['entry_id']).to eq(favourites.entries.last.id)
  end

  # The button is a heart, and a heart is a thing people press twice.
  it 'adds nothing the second time' do
    sign_in user
    post favorite_entry_path(entry)

    expect { post favorite_entry_path(entry) }
      .not_to change { favourites.entries.count }
  end

  # A series filed without its episodes is an entry with nothing to play: it would sit in
  # the favourites channel looking fine and be off air the moment anybody tuned to it.
  it 'brings a series\' episodes with it' do
    series = create(:entry, list: channel, media: 'series', name: 'Babylon 5',
                            imdb: 'tt0000005', position: 2)
    Subentry.create!(entry: series, season: 1, episode: 1, name: 'Midnight on the Firing Line')
    Subentry.create!(entry: series, season: 1, episode: 2, name: 'Soul Hunter')

    sign_in user
    post favorite_entry_path(series)

    copy = favourites.entries.find_by(imdb: 'tt0000005')
    expect(copy.subentries.order(:season, :episode).pluck(:name))
      .to eq(['Midnight on the Firing Line', 'Soul Hunter'])
  end

  # Whose copy this is has nothing to do with who has watched what: that lives per user in
  # UserEntry, and the column on the row is the pre-multi-user leftover.
  it 'does not carry the original\'s watched flag onto the copy' do
    entry.update!(completed: true)

    sign_in user
    post favorite_entry_path(entry)

    expect(favourites.entries.find_by(imdb: 'tt0000001').completed).to be_falsey
  end

  it 'says so rather than guessing when the member has no favourites channel' do
    entry
    user.update!(favorite_list: nil)

    sign_in user
    expect { post favorite_entry_path(entry) }.not_to change { Entry.count }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to be_present
  end

  it 'refuses a visitor with no account' do
    entry
    AppSetting.update_access_mode!('open')

    expect { post favorite_entry_path(entry) }.not_to change { Entry.count }

    expect(response).to have_http_status(:redirect)
  end
end
