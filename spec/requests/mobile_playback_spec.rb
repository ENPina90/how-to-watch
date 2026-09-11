require 'rails_helper'

# The phone view does not play anything. That is what it is for rather than a limitation:
# adding something to a channel while out, marking something watched, reading the listings.
RSpec.describe 'Playback in the phone view', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let!(:entry) { create(:entry, list: list, name: 'The Death of Harvey', imdb: 'tt0000001', position: 1) }

  # A real iPhone string, so the check under test is the one that runs in production.
  let(:phone) { { 'HTTP_USER_AGENT' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15' } }
  let(:desktop) { { 'HTTP_USER_AGENT' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' } }

  before { sign_in user }

  it 'refuses the watch page and says where to go instead' do
    get watch_entry_path(entry), headers: phone

    expect(response).to redirect_to(list_path(list))
    expect(flash[:alert]).to include('full site')
  end

  it 'refuses watch_now' do
    get watch_now_path, params: { imdb: 'tt0000001' }, headers: phone

    expect(response).to have_http_status(:redirect)
  end

  it 'refuses a cable channel' do
    get cable_path, headers: phone

    expect(response).to have_http_status(:redirect)
  end

  # The listings are the one part of cable the phone view keeps: reading what is on is not
  # watching it.
  it 'still serves the cable listings' do
    get cable_guide_path, headers: phone

    expect(response).to be_successful
    expect(response.body).to include('tvguide__grid')
  end

  it 'leaves the full view alone' do
    get watch_entry_path(entry), headers: desktop

    expect(response).to be_successful
  end

  describe 'asking for the full view anyway' do
    it 'plays once the viewer has said so, on the same device' do
      post view_mode_path, params: { mode: 'desktop' }, headers: phone
      get watch_entry_path(entry), headers: phone

      expect(response).to be_successful
    end

    it 'goes back to refusing when they ask for the phone view again' do
      post view_mode_path, params: { mode: 'desktop' }, headers: phone
      post view_mode_path, params: { mode: 'mobile' }, headers: phone
      get watch_entry_path(entry), headers: phone

      expect(response).to have_http_status(:redirect)
    end

    # A phone that asks for the phone view is not the same as a phone that has said
    # nothing: the choice has to survive a desktop user agent too, or "give me the small
    # one" is unsayable anywhere it might be meant.
    it 'gives the phone view to a desktop that asks for it' do
      post view_mode_path, params: { mode: 'mobile' }, headers: desktop
      get watch_entry_path(entry), headers: desktop

      expect(response).to have_http_status(:redirect)
    end

    it 'ignores a mode it does not know and falls back to the device' do
      post view_mode_path, params: { mode: 'tablet-ish' }, headers: phone
      get watch_entry_path(entry), headers: phone

      expect(response).to have_http_status(:redirect)
    end
  end
end
