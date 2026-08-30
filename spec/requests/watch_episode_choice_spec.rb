require 'rails_helper'

# The watch page's episode sidebar built its links from `subentry.source` -- a column
# subentries no longer have, since a source is computed from the provider's template now.
# Every series with episodes 500'd on the way into watch mode.
RSpec.describe 'Watching an episode of a series', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list, media: 'series', name: 'Trek', imdb: 'tt0060028', position: 1) }

  before do
    sign_in user
    @first = entry.subentries.create!(season: 1, episode: 1, name: 'The Cage')
    @second = entry.subentries.create!(season: 1, episode: 2, name: 'The Corbomite Manoeuvre')
  end

  it 'renders rather than raising on a column that is gone' do
    get watch_entry_path(entry)

    expect(response).to be_successful
    expect(response.body).to include('The Cage')
    expect(response.body).to include('The Corbomite Manoeuvre')
  end

  it 'links each episode by id rather than by a stored url' do
    get watch_entry_path(entry)

    # Scoped to the episode list: the page has other inline handlers, which are not what
    # this is about.
    episodes = response.body[/id="episodesListView".*?Entries Channel View/m]

    expect(episodes).to include(watch_entry_path(entry, subentry: @second.id))
    expect(episodes).not_to include('onclick=')
  end

  # Asking for an episode records it, so the embed url and the sidebar both read from the
  # same place a plain visit reads from.
  it 'switches to the episode that was asked for' do
    get watch_entry_path(entry, subentry: @second.id)

    expect(entry.current_subentry_for_user(user)).to eq(@second)
  end

  # The list highlighted this viewer's episode while the panel under it read the entry's
  # own pointer -- a value shared by everyone who opens the entry -- so the two named
  # different episodes on the same screen.
  describe 'the current episode panel' do
    it 'names the episode this viewer is on' do
      get watch_entry_path(entry, subentry: @second.id)

      panel = response.body[/Current Episode.{0,900}/m]

      expect(panel).to include('The Corbomite Manoeuvre')
      expect(panel).to include('Season 1, Episode 2')
    end

    it 'follows the viewer when they pick another' do
      get watch_entry_path(entry, subentry: @second.id)
      get watch_entry_path(entry, subentry: @first.id)

      panel = response.body[/Current Episode.{0,900}/m]

      expect(panel).to include('The Cage')
      expect(panel).not_to include('The Corbomite Manoeuvre')
    end

    it 'does not follow the entry pointer, which belongs to nobody in particular' do
      entry.update!(current: @first)
      get watch_entry_path(entry, subentry: @second.id)

      panel = response.body[/Current Episode.{0,900}/m]

      expect(panel).to include('The Corbomite Manoeuvre')
    end

    it 'shows the episode plot rather than the series one' do
      @second.update!(plot: 'A cube blocks their way.')
      entry.update!(plot: 'A ship explores the galaxy.')

      get watch_entry_path(entry, subentry: @second.id)

      panel = response.body[/Current Episode.{0,900}/m]

      expect(panel).to include('A cube blocks their way.')
      expect(panel).not_to include('A ship explores the galaxy.')
    end
  end

  it 'ignores an episode that is not this series' do
    stray = create(:entry, list: list, media: 'series', name: 'Other', imdb: 'tt1', position: 2)
                    .subentries.create!(season: 1, episode: 1, name: 'Nope')

    get watch_entry_path(entry, subentry: stray.id)

    expect(response).to be_successful
    expect(entry.current_subentry_for_user(user)).not_to eq(stray)
  end
end
