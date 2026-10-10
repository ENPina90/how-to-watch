require 'rails_helper'

# move_to_list's two remove branches had no permission check, so any signed-in member could
# take any channel out of any other by naming the ids. Now either channel's owner may unlink
# the pair, and only the child's owner may pull it out of every parent at once; an admin may
# do either. See User#can_unlink_list?.
RSpec.describe 'Removing a channel from its parent', type: :request do
  let(:parent_owner) { create(:user) }
  let(:child_owner)  { create(:user) }
  let(:stranger)     { create(:user) }
  let(:admin)        { create(:user, :admin) }
  let(:parent)       { create(:list, user: parent_owner, name: 'Westerns') }
  let(:child)        { create(:list, user: child_owner, name: 'Spaghetti Westerns') }

  before { child.add_to_parent(parent) }

  def remove_from_parent
    patch list_move_to_list_path(child, remove_from: parent.id)
  end

  def remove_from_all
    patch list_move_to_list_path(child)
  end

  { 'the parent\'s owner' => :parent_owner, 'the child\'s owner' => :child_owner, 'an admin' => :admin }.each do |who, user|
    it "lets #{who} take it out of the parent" do
      sign_in send(user)
      remove_from_parent

      expect(child.reload.parent_lists).not_to include(parent)
    end
  end

  it 'refuses anybody else' do
    sign_in stranger
    remove_from_parent

    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to include("don't have permission")
    expect(child.reload.parent_lists).to include(parent)
  end

  describe 'removing it from every parent' do
    it 'is the child\'s owner\'s call' do
      sign_in child_owner
      remove_from_all

      expect(child.reload.parent_lists).to be_empty
    end

    it 'is open to an admin' do
      sign_in admin
      remove_from_all

      expect(child.reload.parent_lists).to be_empty
    end

    it 'is not open to the owner of just one of the parents' do
      sign_in parent_owner
      remove_from_all

      expect(child.reload.parent_lists).to include(parent)
    end
  end

  describe 'the remove links' do
    it 'are left off a channel page for a member who may not use them' do
      child.update!(default: true) # the move dropdown shows for anyone on a default channel
      sign_in stranger
      get list_path(child)

      expect(response.body).not_to include(list_move_to_list_path(child, remove_from: parent.id))
      expect(response.body).not_to include('Remove from all parents')
    end

    it 'are on it for the child\'s owner' do
      sign_in child_owner
      get list_path(child)

      expect(response.body).to include(list_move_to_list_path(child, remove_from: parent.id))
      expect(response.body).to include('Remove from all parents')
    end
  end
end
