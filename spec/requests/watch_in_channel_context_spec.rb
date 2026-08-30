require 'rails_helper'

# Clicking an entry on a channel that borrowed it should keep you on that channel. The
# entry's own list is still its home -- editing, deleting, its place in that channel -- but
# the page you are watching from is the one you came from.
RSpec.describe 'Watching from the channel you came from', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:parent) { create(:list, user: user, name: 'List of Lists') }
  let(:child) { create(:list, user: user, name: 'School Night In') }
  let!(:borrowed) { create(:entry, list: child, name: 'Arrival', imdb: 'tt2', position: 1) }

  before do
    sign_in user
    create(:entry, list: parent, name: 'Alien', imdb: 'tt1', position: 1)
    child.add_to_parent(parent)
  end

  it 'sends the channel along with the play link' do
    get list_path(parent, criteria: 'Year')

    expect(response.body).to include(watch_entry_path(borrowed, channel: parent.id))
  end

  it 'leaves a link alone when the entry is already at home' do
    get list_path(child, criteria: 'Position')

    expect(response.body).to include(%(href="#{watch_entry_path(child.entries.first)}"))
  end

  describe 'the watch page' do
    it 'names the channel you came from, not the one the entry lives in' do
      get watch_entry_path(borrowed, channel: parent.id)

      expect(response.body).to include('List of Lists')
      expect(response.body).to include(list_path(parent))
    end

    it 'falls back to the entry’s own channel with no channel given' do
      get watch_entry_path(borrowed)

      expect(response.body).to include('School Night In')
    end

    # A hand-edited id should not let one channel wear another's contents.
    # The left sidebar names every channel you are subscribed to, so this asks the page
    # which channel it resolved rather than which names appear on it.
    it 'refuses a channel that does not hold the entry' do
      stranger = create(:list, user: user, name: 'Unrelated')

      get watch_entry_path(borrowed, channel: stranger.id)

      expect(assigns(:channel)).to eq(child)
    end

    it 'accepts one that holds it through a channel inside it' do
      get watch_entry_path(borrowed, channel: parent.id)

      expect(assigns(:channel)).to eq(parent)
    end

    it 'lists the channel’s whole sequence beside it, borrowed entries and all' do
      get watch_entry_path(borrowed, channel: parent.id)

      expect(response.body).to include('Alien')
      expect(response.body).to include('Arrival')
    end

    it 'keeps the channel on the links in that list' do
      get watch_entry_path(borrowed, channel: parent.id)

      expect(response.body).to include(watch_entry_path(borrowed, channel: parent.id))
    end

    # Position is a number within the channel that owns the entry; a borrowed entry has
    # none in the channel borrowing it, so that is still recorded at home.
    it 'records the position in the channel that owns the entry' do
      get watch_entry_path(borrowed, channel: parent.id)

      expect(child.position_for_user(user).current_position).to eq(borrowed.position)
      expect(parent.position_for_user(user)).to be_nil
    end
  end

  # Every way onto the watch page from a channel that borrowed the entry.
  describe 'the ways in' do
    it 'from a card in a grouped view' do
      get list_path(parent, criteria: 'Year')

      expect(response.body).to include(watch_entry_path(borrowed, channel: parent.id))
    end

    it 'from an entry inside an opened channel row' do
      get list_nested_entries_path(child, channel: parent.id)

      expect(response.body).to include(watch_entry_path(borrowed, channel: parent.id))
    end

    # Up Next samples at random, so this channel holds nothing of its own: the only thing
    # it can suggest is the borrowed entry.
    it 'from Up Next' do
      hub = create(:list, user: user, name: 'Only Borrowed')
      child.add_to_parent(hub)

      get list_path(hub, criteria: 'Year')

      picks = response.body[/data-randomize-target="picks".*?Pick for me[^<]*<\/a>/m]

      expect(picks).to include("channel=#{hub.id}")
    end

    # The row opens the frame with the channel it is being opened on, or the frame would
    # not know it was nested at all.
    it 'is what the row asks the frame for' do
      get list_path(parent, criteria: 'Position')

      expect(response.body).to include(list_nested_entries_path(child, channel: parent.id))
    end

    it 'leaves the channel’s own page alone' do
      get list_nested_entries_path(child)

      expect(response.body).to include(%(href="#{watch_entry_path(borrowed)}"))
    end

    it 'refuses a channel that does not hold this one' do
      stranger = create(:list, user: user, name: 'Unrelated')

      get list_nested_entries_path(child, channel: stranger.id)

      expect(response.body).not_to include("channel=#{stranger.id}")
    end
  end

  # The arrows step through the channel you are watching from. They used to walk the
  # positions of whichever channel the entry lived in, which handed you back to the
  # sub-channel on the first click.
  describe 'stepping with the arrows' do
    # The channel runs [its own Alien, then the nested channel's Arrival].
    let(:own) { parent.entries.find_by(name: 'Alien') }

    it 'goes to the next thing on this channel, across the channels inside it' do
      patch increment_current_entry_path(own, mode: 'watch', channel: parent.id)

      expect(response).to redirect_to(watch_entry_path(borrowed, channel: parent.id))
    end

    it 'comes back the same way' do
      patch decrement_current_entry_path(borrowed, mode: 'watch', channel: parent.id)

      expect(response).to redirect_to(watch_entry_path(own, channel: parent.id))
    end

    it 'stays put at the end rather than falling out of the channel' do
      patch increment_current_entry_path(borrowed, mode: 'watch', channel: parent.id)

      expect(response).to redirect_to(watch_entry_path(borrowed, channel: parent.id))
    end

    it 'walks the entry’s own channel when that is where you are' do
      other = create(:entry, list: child, name: 'Solaris', imdb: 'tt8', position: 2)

      patch increment_current_entry_path(borrowed, mode: 'watch', channel: child.id)

      expect(response).to redirect_to(watch_entry_path(other, channel: child.id))
    end

    it 'shuffles within the channel, not within the entry’s own' do
      patch shuffle_current_entry_path(borrowed, mode: 'watch', channel: parent.id)

      # The only other unwatched thing under this channel.
      expect(response).to redirect_to(watch_entry_path(own, channel: parent.id))
    end

    it 'carries the channel on the arrows themselves' do
      get watch_entry_path(borrowed, channel: parent.id)

      expect(response.body).to include(
        CGI.escapeHTML(increment_current_entry_path(borrowed, mode: 'watch', channel: parent.id))
      )
    end
  end

  describe 'the sequence a channel of channels reads as' do
    it 'runs its own entries and the nested ones as one list' do
      expect(parent.watch_sequence.map(&:name)).to eq(%w[Alien Arrival])
    end

    it 'puts a nested channel where that channel sits in the order' do
      parent.child_relationships.find_by(child_list: child).update!(position: 0)

      expect(parent.watch_sequence.map(&:name)).to eq(%w[Arrival Alien])
    end
  end
end
