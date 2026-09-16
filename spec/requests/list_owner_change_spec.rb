# frozen_string_literal: true

require 'rails_helper'

# Handing a channel to somebody else, from the channel's own edit page.
#
# An admin's doing, and gated on both sides rather than only hidden: `can_edit_list?` is
# true for *any* member on a default channel, so the edit page is reachable by people who
# must not be able to reassign what they are editing.
RSpec.describe 'Changing who a channel belongs to', type: :request do
  let(:admin) { create(:user, :admin, username: 'Boss') }
  let(:owner) { create(:user, username: 'Casual') }
  let(:list) { create(:list, user: owner, name: 'Westerns') }

  describe 'the field' do
    it 'offers an admin every account, with the admins starred' do
      sign_in admin

      get edit_list_path(list)

      expect(response.body).to include('name="list[user_id]"')
      expect(response.body).to include('Boss ★')
      expect(response.body).to include('Casual')
    end

    it 'is not offered to the member who owns the channel' do
      sign_in owner

      get edit_list_path(list)

      expect(response.body).not_to include('name="list[user_id]"')
    end
  end

  describe 'handing it over' do
    it 'moves the channel to the chosen account' do
      sign_in admin

      patch list_path(list), params: { list: { user_id: admin.id } }

      expect(list.reload.user).to eq(admin)
    end

    it 'ignores the field when a member who is not an admin sends it by hand' do
      default_channel = create(:list, user: owner, name: 'Channel One', default: true, cable_position: 1)
      intruder = create(:user)
      sign_in intruder

      patch list_path(default_channel), params: { list: { user_id: intruder.id } }

      expect(default_channel.reload.user).to eq(owner)
    end

    # A favourite must be a channel you created, so the previous owner's would be invalid the
    # moment the channel moved -- and would fail their next save, on an unrelated form.
    it 'releases the previous owner’s favourite' do
      owner.favorite!(list)
      sign_in admin

      patch list_path(list), params: { list: { user_id: admin.id } }

      expect(owner.reload.favorite_list_id).to be_nil
      expect(owner).to be_valid
    end

    it 'leaves the favourite alone when the channel has not moved' do
      owner.favorite!(list)
      sign_in admin

      patch list_path(list), params: { list: { name: 'Renamed' } }

      expect(owner.reload.favorite_list_id).to eq(list.id)
    end
  end
end
