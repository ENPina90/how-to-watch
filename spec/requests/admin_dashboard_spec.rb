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

  describe 'the deployment panel' do
    let(:admin) { create(:user, :admin) }

    before { sign_in admin }

    def stub_deployment(web:, worker:, beats: [Time.current])
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('RAILWAY_GIT_COMMIT_SHA').and_return(web)
      allow(Sidekiq).to receive(:redis).and_return({ sha: worker, booted_at: Time.current.iso8601 }.to_json)
      allow(Sidekiq::ProcessSet).to receive(:new).and_return(beats.map { |b| { 'beat' => b.to_f } })
    end

    # The failure this panel exists for: the worker on an older build fails every job it
    # does not recognise, and nothing else on the site says so.
    it 'shouts when web and worker are on different builds' do
      stub_deployment(web: 'aaaaaaa1', worker: 'bbbbbbb2')

      get admin_dashboard_path

      expect(response.body).to include('different builds')
      expect(response.body).to include('aaaaaaa')
      expect(response.body).to include('bbbbbbb')
    end

    it 'shouts when nothing is processing the queue' do
      stub_deployment(web: 'aaaaaaa1', worker: 'aaaaaaa1', beats: [])

      get admin_dashboard_path

      expect(response.body).to include('No worker is running')
    end

    it 'says nothing alarming when the two agree' do
      stub_deployment(web: 'aaaaaaa1', worker: 'aaaaaaa1')

      get admin_dashboard_path

      expect(response.body).not_to include('different builds')
      expect(response.body).not_to include('No worker is running')
    end

    # Locally Railway injects nothing, and a panel that cried mismatch every run would be
    # ignored by the time it mattered.
    it 'explains itself rather than warning when it knows nothing' do
      stub_deployment(web: nil, worker: nil, beats: [])
      allow(Sidekiq).to receive(:redis).and_return(nil)

      get admin_dashboard_path

      expect(response.body).not_to include('different builds')
      expect(response.body).to include('RAILWAY_GIT_COMMIT_SHA')
    end

    it 'renders even with no Redis at all' do
      allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError)
      allow(Sidekiq::ProcessSet).to receive(:new).and_raise(RedisClient::CannotConnectError)

      get admin_dashboard_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'resetting which provider channels play through' do
    let!(:target) do
      Source.create!(name: 'Player', slug: 'framerelay', kind: 'imdb', active: true, position: 1,
                     templates: { 'movie' => 'https://framerelay.dev/embed/movie?imdb=%{imdb}' })
    end
    let!(:drive) do
      Source.create!(name: 'Google Drive', slug: 'google-drive', kind: 'direct', active: true,
                     position: 9, templates: { 'default' => 'https://drive.google.com/file/d/%{source_key}/preview' })
    end

    it 'moves the channels and says what it did' do
      sign_in admin
      channel = create(:list, user: admin, provider: nil)

      post reset_source_admin_dashboard_path, params: { source_id: target.id }

      expect(response).to redirect_to(admin_dashboard_path)
      expect(channel.reload.provider).to eq(target)
      expect(flash[:notice]).to match(/plays? through Player/)
    end

    # The templates of a direct provider take a source_key, which no channel has.
    it 'refuses a provider that does not play by imdb id' do
      sign_in admin
      channel = create(:list, user: admin, provider: nil)

      post reset_source_admin_dashboard_path, params: { source_id: drive.id }

      expect(channel.reload.provider).to be_nil
      expect(flash[:alert]).to match(/IMDb id/)
    end

    # The select starts blank on purpose, so submitting without choosing must not guess.
    it 'refuses a blank choice rather than picking one' do
      sign_in admin
      channel = create(:list, user: admin, provider: nil)

      post reset_source_admin_dashboard_path, params: { source_id: '' }

      expect(channel.reload.provider).to be_nil
      expect(flash[:alert]).to be_present
    end

    it 'refuses a provider that has been deactivated' do
      sign_in admin
      target.update!(active: false)

      post reset_source_admin_dashboard_path, params: { source_id: target.id }

      expect(flash[:alert]).to be_present
    end

    # It rewrites rows across two tables, so it is gated exactly like the rest of /admin.
    it 'turns away a user who is not an admin' do
      sign_in create(:user)
      channel = create(:list, user: admin, provider: nil)

      post reset_source_admin_dashboard_path, params: { source_id: target.id }

      expect(response).to redirect_to(root_path)
      expect(channel.reload.provider).to be_nil
    end

    it 'turns away a signed-out visitor' do
      post reset_source_admin_dashboard_path, params: { source_id: target.id }

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
