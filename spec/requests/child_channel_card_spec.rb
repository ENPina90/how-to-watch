require 'rails_helper'

# A channel inside another channel is shown as a card in the shape of a series card: the
# poster of wherever you are up to in it, and arrows that step through its entries the way
# a series card steps through its episodes.
RSpec.describe 'The card for a channel inside a channel', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:parent) { create(:list, user: user, name: 'Nights In') }
  let(:child) { create(:list, user: user, name: 'Noir') }

  before do
    sign_in user
    child.child_relationships # touch
    %w[Alien Aliens Arrival].each_with_index do |name, i|
      create(:entry, list: child, name: name, imdb: "tt00#{i}", position: i + 1)
    end
    child.add_to_parent(parent)
  end

  def card
    response.body[/<turbo-frame id="#{ActionView::RecordIdentifier.dom_id(child)}">.*?<\/turbo-frame>/m]
  end

  it 'wears the same card shape as an entry, with a mark saying it is not one' do
    get list_path(parent)

    expect(card).to include('grid-card channel-card')
    expect(card).to include('channel-card__badge')
    expect(card).to include('card-picture')
  end

  it 'shows where you are up to, and how far through' do
    get list_path(parent)

    expect(card).to include('Alien')
    expect(card).to include('1 of 3')
  end

  it 'offers the arrows a series card offers its episodes' do
    get list_path(parent)

    expect(card).to include(list_next_entry_path(child))
    expect(card).to include(list_previous_entry_path(child))
  end

  describe 'stepping through it' do
    it 'moves forward one entry' do
      patch list_next_entry_path(child)

      expect(child.position_for_user(user).current_entry.name).to eq('Aliens')
    end

    it 'moves back again' do
      patch list_next_entry_path(child)
      patch list_next_entry_path(child)
      patch list_previous_entry_path(child)

      expect(child.position_for_user(user).current_entry.name).to eq('Aliens')
    end

    it 'stays put at either end rather than falling off' do
      patch list_previous_entry_path(child)

      expect(child.position_for_user(user).current_entry.name).to eq('Alien')
    end

    # It is this user's place in the channel, not the channel's own state.
    it 'moves nobody else' do
      other = create(:user)
      child.position_for_user!(other)

      patch list_next_entry_path(child)

      expect(child.position_for_user(other).current_entry.name).to eq('Alien')
    end

    it 'comes back to the page the card is on, for the frame to be swapped out of' do
      patch list_next_entry_path(child), headers: { 'HTTP_REFERER' => list_path(parent) }

      expect(response).to redirect_to(list_path(parent))
    end
  end

  it 'shows an empty channel as empty rather than breaking' do
    empty = create(:list, user: user, name: 'Nothing Yet')
    empty.add_to_parent(parent)

    get list_path(parent)

    frame = response.body[/<turbo-frame id="#{ActionView::RecordIdentifier.dom_id(empty)}">.*?<\/turbo-frame>/m]
    expect(frame).to include('Empty')
    expect(frame).to include('Nothing in here yet')
  end
end
