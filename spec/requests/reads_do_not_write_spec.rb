require 'rails_helper'

# Rendering used to insert rows: `completed_by?` and `position_for_user` were both
# find_or_create_by, so simply opening a list wrote one user_entries row per entry on the
# page, and opening the index wrote a user_list_positions row per card.
RSpec.describe 'Reads do not write', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  describe 'viewing a list' do
    it 'creates no user_entries rows' do
      create(:entry, list: list, name: 'One', position: 1)
      create(:entry, list: list, name: 'Two', position: 2)

      expect {
        get list_path(list)
      }.not_to change(UserEntry, :count)

      expect(response).to be_successful
    end

    it 'creates no user_list_positions rows' do
      create(:entry, list: list, position: 1)

      expect {
        get list_path(list)
      }.not_to change(UserListPosition, :count)
    end
  end

  describe 'viewing the lists index' do
    it 'creates no tracking rows for the cards it renders' do
      create(:list, user: user, name: 'Another list').tap do |other|
        create(:entry, list: other, position: 1)
      end
      create(:entry, list: list, position: 1)

      expect {
        get lists_path
      }.not_to change(UserListPosition, :count)

      expect {
        get lists_path
      }.not_to change(UserEntry, :count)

      expect(response).to be_successful
    end
  end

  describe 'watching an entry' do
    it 'does record a position, because that is a real action' do
      entry = create(:entry, list: list, position: 1)

      expect {
        get watch_entry_path(entry)
      }.to change(UserListPosition, :count).by(1)

      expect(list.position_for_user(user).current_position).to eq(1)
    end
  end

  describe 'completion state' do
    it 'reports false for an untracked entry without creating a row' do
      entry = create(:entry, list: list, position: 1)

      expect { expect(entry.completed_by?(user)).to be false }.not_to change(UserEntry, :count)
    end

    it 'still records completion when the user marks it watched' do
      entry = create(:entry, list: list, position: 1)

      expect {
        patch complete_entry_path(entry)
      }.to change(UserEntry, :count).by(1)

      expect(entry.completed_by?(user)).to be true
    end
  end
end
