require 'rails_helper'

# A member's favourite channel: the one "Add to Favourites" files into and the one the
# phone view opens on. It used to be whichever channel carried the `mobile` flag -- set
# once when the account was created and never movable -- and is now a column on the member,
# set from the channel's edit page.
RSpec.describe 'The favourite channel', :needs_provider, type: :request do
  let(:member) { create(:user) }
  let(:channel) { create(:list, user: member, name: 'Noir') }

  describe 'the channel every account starts with' do
    it 'is named for the member and is their favourite' do
      user = User.create!(email: 'ripley@example.com', password: 'password')

      expect(user.lists.first.name).to eq("Ripley's Watchlist")
      expect(user.reload.favorite_list).to eq(user.lists.first)
    end

    it 'is named from the username when there is one' do
      user = User.create!(email: 'a@example.com', password: 'password', username: 'bogart')

      expect(user.favorite_list.name).to eq("Bogart's Watchlist")
    end
  end

  describe 'the control on the edit page' do
    it 'offers to set an unfavourited channel, naming the one it would replace' do
      sign_in member

      get edit_list_path(channel)

      expect(response.body).to include('Set as Favourite')
      expect(response.body).to include(list_toggle_favorite_path(channel))
      # Escaped, because the auto-created channel's name carries an apostrophe.
      expect(response.body).to include(ERB::Util.html_escape(member.favorite_list.name))
    end

    it 'offers to remove it once the channel is the favourite' do
      member.favorite!(channel)
      sign_in member

      get edit_list_path(channel)

      expect(response.body).to include('Remove as Favourite')
      expect(response.body).not_to include('Set as Favourite')
    end

    # A default channel is editable by anybody, which is not the same as favouritable.
    it 'is absent on a channel the member does not own' do
      other = create(:list, user: create(:user), name: 'Westerns', default: true)
      sign_in member

      get edit_list_path(other)

      expect(response.body).not_to include(list_toggle_favorite_path(other))
    end
  end

  describe 'setting it' do
    it 'moves the favourite off whatever held it, since there is only one' do
      starting = member.favorite_list
      sign_in member

      patch list_toggle_favorite_path(channel)

      expect(member.reload.favorite_list).to eq(channel)
      expect(member).not_to be_favorite(starting)
    end

    it 'clears it when the channel already is the favourite' do
      member.favorite!(channel)
      sign_in member

      patch list_toggle_favorite_path(channel)

      expect(member.reload.favorite_list).to be_nil
    end

    it 'refuses a channel the member did not create' do
      other = create(:list, user: create(:user), name: 'Westerns', default: true)
      sign_in member

      patch list_toggle_favorite_path(other)

      expect(member.reload.favorite_list).not_to eq(other)
      expect(flash[:alert]).to eq('You can only favourite a channel you created.')
    end

    it 'will not be talked into someone else\'s channel by a direct write' do
      other = create(:list, user: create(:user), name: 'Westerns')

      expect(member.favorite!(other)).to be(false)
      expect(member.update(favorite_list: other)).to be(false)
      expect(member.errors[:favorite_list]).to include('must be a channel you created')
    end
  end

  describe 'what reads it' do
    it 'is where Add to Favourites files an entry' do
      member.favorite!(channel)
      sign_in member

      expect(ImdbEntryImporter).to receive(:new).with(hash_including(list: channel)).and_call_original

      post '/lists/add_to_favorites', params: { imdb: 'tt0000000' }
    end

    it 'says so plainly when the member has no favourite left' do
      member.unfavorite!
      sign_in member

      post '/lists/add_to_favorites', params: { imdb: 'tt0000000' }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('Favorites channel not found')
    end
  end

  describe 'when the channel goes away' do
    it 'leaves the member with no favourite rather than a dangling one' do
      member.favorite!(channel)

      channel.destroy

      expect(member.reload.favorite_list_id).to be_nil
    end

    it 'does not stand in the way of deleting the account' do
      member.favorite!(channel)

      expect { member.destroy }.to change(User, :count).by(-1)
    end
  end
end
