require 'rails_helper'

# Who gets in without an account, per the access mode an admin sets on the dashboard.
RSpec.describe 'Site access modes', :needs_provider, type: :request do
  let(:owner) { create(:user) }
  let(:list) { create(:list, user: owner, name: 'Public channel') }
  let!(:entry) { create(:entry, list: list, name: 'Alien', media: 'movie', imdb: 'tt0078748', position: 1) }

  def set_mode(mode)
    AppSetting.update_access_mode!(mode)
  end

  describe 'secure' do
    before { set_mode('secure') }

    it 'sends a signed-out visitor to sign in, from anywhere' do
      get lists_path
      expect(response).to redirect_to(new_user_session_path)

      get list_path(list)
      expect(response).to redirect_to(new_user_session_path)

      get watch_entry_path(entry)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'moderate' do
    before { set_mode('moderate') }

    it 'lets a signed-out visitor browse' do
      get lists_path
      expect(response).to be_successful

      get list_path(list)
      expect(response).to be_successful
    end

    it 'shows the public channels and leaves the signed-in rows out' do
      create(:list, user: owner, name: 'Hidden channel', private: true)

      get lists_path

      expect(response.body).to include('Public channel')
      expect(response.body).not_to include('Hidden channel')
      # The heading itself, not the HTML comment above it, which is in the view either way.
      expect(response.body).not_to include('<h3 class="row-title">Your Channels</h3>')
    end

    it 'still asks for an account before anything plays' do
      get watch_entry_path(entry)
      expect(response).to redirect_to(new_user_session_path)

      get watch_now_path(imdb: 'tt0078748', title: 'Alien', type: 'movie')
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'open' do
    before { set_mode('open') }

    it 'lets a signed-out visitor watch' do
      get watch_entry_path(entry)
      expect(response).to be_successful

      get watch_now_path(imdb: 'tt0078748', title: 'Alien', type: 'movie')
      expect(response).to be_successful
    end

    it 'plays a channel from its own button' do
      get list_watch_current_path(list)

      expect(response).to redirect_to(watch_entry_path(entry, channel: list.id))
    end

    it 'leaves out the controls that would need an account' do
      get watch_entry_path(entry)

      expect(response.body).not_to include(increment_current_entry_path(entry, mode: 'watch', channel: list.id))
      expect(response.body).not_to include(list_subscribe_path(list))
    end
  end

  # Opening the site up is about what is public. A private channel stays shut, and so does
  # anything that would read it out sideways.
  describe 'private channels' do
    let(:hidden) { create(:list, user: owner, name: 'Hidden channel', private: true) }
    let!(:hidden_entry) { create(:entry, list: hidden, name: 'Solaris', media: 'movie', position: 1) }

    before { AppSetting.update_access_mode!('open') }

    it 'refuses a signed-out visitor who has the URL' do
      get list_path(hidden)
      expect(response).to redirect_to(new_user_session_path)

      get list_entry_index_path(hidden)
      expect(response).to redirect_to(new_user_session_path)

      get list_watch_current_path(hidden)
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'refuses an entry that lives in one' do
      get watch_entry_path(hidden_entry)

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'does not let one be named as the channel a public entry is watched from' do
      hidden.child_relationships.create!(child_list: list, position: 1)

      get watch_entry_path(entry, channel: hidden.id)

      expect(response).to be_successful
      expect(response.body).not_to include('Hidden channel')
    end

    it 'still lets the owner in' do
      sign_in owner

      get list_path(hidden)

      expect(response).to be_successful
    end
  end

  # The rule that holds whatever the table says: a guest never writes.
  describe 'every mode' do
    AppSetting::ACCESS_MODES.each do |mode|
      it "refuses a signed-out write in #{mode} mode" do
        set_mode(mode)

        expect { post lists_path, params: { list: { name: 'Mine' } } }.not_to change(List, :count)
        expect(response).to redirect_to(new_user_session_path)

        expect { delete entry_path(entry) }.not_to change(Entry, :count)
        expect(response).to redirect_to(new_user_session_path)

        patch list_subscribe_path(list)
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  it 'is secure until an admin says otherwise' do
    expect(AppSetting.current.access_mode).to eq('secure')
  end
end
