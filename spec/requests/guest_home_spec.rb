require 'rails_helper'

# The home page as a signed-out visitor sees it, where the access mode lets one in. It used
# to be the public shelf on a cream page with a stand-by card on every channel and no
# sidebar -- nothing on it that said what any channel held, or what was on.
RSpec.describe 'The home page signed out', :needs_provider, type: :request do
  let(:owner) { create(:user) }
  let!(:westerns) { create(:list, user: owner, name: 'Westerns') }
  let!(:shane) { create(:entry, list: westerns, name: 'Shane', pic: 'https://example.com/shane.jpg', position: 1) }

  before { AppSetting.update_access_mode!('moderate') }

  it 'renders dark' do
    get lists_path

    expect(response.body).to match(/<body class="[^"]*\bdark-mode\b/)
  end
end
