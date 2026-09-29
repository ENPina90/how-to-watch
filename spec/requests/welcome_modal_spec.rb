# frozen_string_literal: true

require 'rails_helper'

# The first-visit welcome. It is drawn by the server for a signed-out visitor who has not
# been welcomed yet, and the page's controller leaves the cookie that stops it being drawn
# again. The sign-in page is used throughout because every access mode lets a visitor
# reach it.
RSpec.describe 'The welcome modal', type: :request do
  def welcome
    response.body[%r{<div class="modal fade welcome-modal".*?</div>\s*</div>\s*</div>\s*</div>}m]
  end

  it 'greets a signed-out visitor on their first page' do
    get new_user_session_path

    expect(welcome).to be_present
    expect(welcome).to include('data-controller="welcome"')
  end

  it 'is not drawn once the visitor has been welcomed' do
    cookies[:welcomed] = '1'

    get new_user_session_path

    expect(welcome).to be_nil
  end

  it 'is not drawn for anyone signed in' do
    sign_in create(:user)

    get lists_path

    expect(response.body).not_to include('welcome-modal')
  end

  describe 'on a phone' do
    let(:iphone) { 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148' }

    it 'is not drawn' do
      get new_user_session_path, headers: { 'User-Agent' => iphone }

      expect(welcome).to be_nil
    end

    it 'is not drawn even when asked for' do
      get new_user_session_path(welcome: 1), headers: { 'User-Agent' => iphone }

      expect(welcome).to be_nil
    end
  end

  describe 'on demand' do
    it 'has /first send you to the home page asking for it' do
      get '/first'

      expect(response).to redirect_to('/?welcome=1')
    end

    it 'is drawn with ?welcome=1 after it has been seen' do
      cookies[:welcomed] = '1'

      get new_user_session_path(welcome: 1)

      expect(welcome).to be_present
    end

    it 'is drawn with ?welcome=1 for someone signed in' do
      sign_in create(:user)

      get lists_path(welcome: 1)

      expect(response.body).to include('welcome-modal')
    end
  end

  it 'offers the cable, the sign-up page, search and the tour' do
    get new_user_session_path

    expect(welcome).to include(%(href="#{cable_path}"))
    expect(welcome).to include(%(href="#{new_user_registration_path}"))
    expect(welcome).to include('data-action="welcome#search"')
    expect(welcome).to include('Take Tour')
  end

  it 'draws the adblock advice hidden, for the controller to show where it applies' do
    get new_user_session_path

    expect(welcome).to match(/<p class="welcome-modal__adblock"[^>]*\bhidden\b/)
  end

  describe 'the name it welcomes you to' do
    it 'falls back to HowToWatch on an address nobody chose' do
      host! 'how-to-watch-production.up.railway.app'

      get new_user_session_path

      expect(welcome).to include('Welcome to HowToWatch')
    end

    it 'uses the domain the site was reached at' do
      host! 'www.couchcable.com'

      get new_user_session_path

      expect(welcome).to include('Welcome to couchcable.com')
    end

    it 'takes SITE_NAME over the domain' do
      host! 'couchcable.com'
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SITE_NAME').and_return('Couch Cable')

      get new_user_session_path

      expect(welcome).to include('Welcome to Couch Cable')
    end
  end
end
