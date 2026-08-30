require 'rails_helper'

RSpec.describe 'The admin dashboard', type: :request do
  let(:admin) { create(:user, :admin) }

  describe 'who can open it' do
    it 'renders for an admin' do
      sign_in admin

      get admin_dashboard_path

      expect(response).to be_successful
      expect(response.body).to include('Dashboard')
    end

    it 'turns away a signed-in user who is not an admin' do
      sign_in create(:user)

      get admin_dashboard_path

      expect(response).to redirect_to(root_path)
    end

    it 'turns away a signed-out visitor, whatever the access mode' do
      AppSetting.update_access_mode!('open')

      get admin_dashboard_path

      expect(response).to redirect_to(new_user_session_path)
    end

    # The same reasoning that keeps /sidekiq out of an impersonated session: the admin is
    # looking at the site as someone else, and the dashboard is not part of that.
    it 'turns away an admin who is viewing as somebody else' do
      sign_in admin
      post impersonate_user_path(create(:user))

      get admin_dashboard_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'setting the access mode' do
    before { sign_in admin }

    it 'saves a mode' do
      patch admin_dashboard_path, params: { app_setting: { access_mode: 'moderate' } }

      expect(AppSetting.current.access_mode).to eq('moderate')
      expect(response).to redirect_to(admin_dashboard_path)
    end

    it 'refuses anything that is not one of the three' do
      AppSetting.update_access_mode!('moderate')

      patch admin_dashboard_path, params: { app_setting: { access_mode: 'everything' } }

      expect(AppSetting.current.access_mode).to eq('moderate')
      expect(flash[:alert]).to be_present
    end

    it 'takes effect on the next request' do
      patch admin_dashboard_path, params: { app_setting: { access_mode: 'moderate' } }
      sign_out admin

      get lists_path

      expect(response).to be_successful
    end
  end

  describe 'the numbers' do
    it 'counts what is on the site' do
      owner = create(:user)
      list = create(:list, user: owner)
      create(:entry, list: list, name: 'Alien')
      sign_in admin

      get admin_dashboard_path

      expect(response).to be_successful
      stats = AdminStatistics.new
      expect(stats.users_total).to eq(User.count)
      expect(stats.entries_total).to eq(1)
      expect(stats.lists_total).to eq(List.count)
    end

    it 'reports a day nobody came as zero rather than leaving it out' do
      expect(AdminStatistics.new.daily_visits.length).to eq(AdminStatistics::WINDOW)
      expect(AdminStatistics.new.daily_visits.map { |day| day[:visits] }).to all(eq(0))
    end
  end
end
