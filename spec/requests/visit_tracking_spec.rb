require 'rails_helper'

# What the dashboard counts. One row per browser per day, so the table grows with the
# audience rather than with the traffic.
RSpec.describe 'Visit tracking', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  it 'records a visit the first time a browser opens a page' do
    sign_in user

    expect { get lists_path }.to change(Visit, :count).by(1)
    expect(Visit.last.page_views).to eq(1)
    expect(Visit.last.user_id).to eq(user.id)
  end

  it 'counts the second page against the same visit' do
    sign_in user
    get lists_path

    expect { get lists_path }.not_to change(Visit, :count)
    expect(Visit.last.page_views).to eq(2)
  end

  it 'keeps a day of its own' do
    sign_in user
    get lists_path

    travel_to(1.day.from_now) do
      expect { get lists_path }.to change(Visit, :count).by(1)
    end
  end

  it 'records a signed-out visitor without knowing anything about them' do
    AppSetting.update_access_mode!('moderate')

    get lists_path

    expect(Visit.count).to eq(1)
    expect(Visit.last.user_id).to be_nil
    expect(Visit.last.visitor_token).to be_present
  end

  # A redirect is the same visit arriving somewhere else, and counting both would double
  # every sign-in.
  it 'does not count a redirect' do
    expect { get lists_path }.not_to change(Visit, :count)
  end

  it 'does not count the health check' do
    expect { get '/health' }.not_to change(Visit, :count)
  end

  it 'names the same browser once when it signs in mid-visit' do
    AppSetting.update_access_mode!('moderate')
    get lists_path
    sign_in user

    expect { get lists_path }.not_to change(Visit, :count)
    expect(Visit.last.user_id).to eq(user.id)
  end
end
