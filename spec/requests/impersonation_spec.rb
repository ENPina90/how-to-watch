require 'rails_helper'

# "View as another user" swaps `current_user`, which is what every permission check in
# the app reads. The failure mode is silent and it is the one that matters: an admin
# checks a page "as" a normal user, still sees admin-only controls because something
# consulted the real account, and ships a page non-admins cannot use. These pin the swap
# to `current_user` and keep the way back reachable.
RSpec.describe 'Viewing the site as another user', :needs_provider, type: :request do
  let(:admin)   { create(:user, :admin, username: 'Boss') }
  let(:regular) { create(:user, username: 'Casual') }

  describe 'an admin' do
    before { sign_in admin }

    it 'switches the session to the other user' do
      post impersonate_user_path(regular)

      expect(response).to redirect_to(root_path)
      expect(session[:impersonated_user_id]).to eq(regular.id)
    end

    it 'loses admin permissions while viewing as a non-admin' do
      other_list = create(:list, user: create(:user), default: false, private: false)

      # Editing someone else's list is an admin-only power (User#can_edit_list?).
      patch list_path(other_list), params: { list: { name: 'Renamed by admin' } }
      expect(other_list.reload.name).to eq('Renamed by admin')

      post impersonate_user_path(regular)
      patch list_path(other_list), params: { list: { name: 'Renamed while impersonating' } }

      expect(other_list.reload.name).to eq('Renamed by admin')
    end

    it 'stops seeing what only an admin can see' do
      # The home page shows admins every list, private ones included; everyone else sees
      # only public or subscribed ones.
      secret = create(:list, user: create(:user), name: 'Someone private channel', private: true)

      get root_path
      expect(response.body).to include(secret.name)

      post impersonate_user_path(regular)
      get root_path

      expect(response.body).not_to include(secret.name)
    end

    it 'sees the impersonated user own library' do
      yours = create(:list, user: regular, name: 'Casual channel')
      regular.subscribe_to!(yours)

      post impersonate_user_path(regular)
      get root_path

      expect(response.body).to include('Casual channel')
    end

    it 'is refused a switch to itself' do
      post impersonate_user_path(admin)

      expect(session[:impersonated_user_id]).to be_nil
    end

    it 'gets back to its own account' do
      post impersonate_user_path(regular)

      delete stop_impersonating_path

      expect(session[:impersonated_user_id]).to be_nil
      get root_path
      expect(response.body).to include('Boss')
    end

    it 'can switch straight from one user to another' do
      # While viewing as a non-admin, `current_user.admin?` is false. The guard has to
      # read the real account or this switch 403s and the menu is a dead end.
      third = create(:user, username: 'Third')

      post impersonate_user_path(regular)
      post impersonate_user_path(third)

      expect(session[:impersonated_user_id]).to eq(third.id)
    end
  end

  describe 'the header' do
    it 'offers the switch to an admin' do
      sign_in admin
      regular # create it

      get root_path

      expect(response.body).to include('View as')
      expect(response.body).to include(impersonate_user_path(regular))
    end

    it 'offers nothing to a normal user' do
      sign_in regular
      admin # create it

      get root_path

      expect(response.body).not_to include('View as')
      expect(response.body).not_to include(impersonate_user_path(admin))
    end

    it 'keeps the way back visible while impersonating' do
      sign_in admin
      post impersonate_user_path(regular)

      get root_path

      expect(response.body).to include('Return to admin')
      expect(response.body).to include('Viewing as')
    end
  end

  describe 'the admin-only dashboard' do
    # /sidekiq is mounted through Devise's route-level `authenticate`, which only ever
    # sees the Warden user -- still the admin while they are viewing as someone else.
    it 'is reachable by an admin' do
      sign_in admin

      get '/sidekiq'

      expect(response).not_to have_http_status(:not_found)
    end

    it 'is not reachable while viewing as another user' do
      sign_in admin
      post impersonate_user_path(regular)

      get '/sidekiq'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'a normal user' do
    before { sign_in regular }

    it 'cannot start impersonating' do
      post impersonate_user_path(admin)

      expect(session[:impersonated_user_id]).to be_nil
      expect(flash[:alert]).to be_present
    end
  end

  describe 'a stale session' do
    before { sign_in admin }

    it 'drops the impersonation when the account is gone' do
      post impersonate_user_path(regular)
      regular.lists.destroy_all # users.lists has no dependent: option
      regular.destroy

      get root_path

      expect(response).to be_successful
      expect(session[:impersonated_user_id]).to be_nil
    end

    it 'drops the impersonation when the admin flag is revoked' do
      post impersonate_user_path(regular)
      admin.update!(admin: false)

      get root_path

      expect(session[:impersonated_user_id]).to be_nil
    end
  end

  describe 'signing out' do
    it 'does not leave the impersonation behind for the next session' do
      sign_in admin
      post impersonate_user_path(regular)

      delete destroy_user_session_path

      expect(session[:impersonated_user_id]).to be_nil
    end
  end
end
