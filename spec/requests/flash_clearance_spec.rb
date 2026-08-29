require 'rails_helper'

# Flashes and toasts are fixed to the bottom-right corner, which is exactly where the right
# sidebar is on a channel page -- they were being read half at a time.
RSpec.describe 'Messages clearing the sidebar', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  it 'marks the page so the corner can be cleared' do
    create(:entry, list: list, position: 1)

    get list_path(list)

    # The sidebar's own controller sets the body class; the flash reads it.
    expect(response.body).to include('data-controller="channel-sidebar"')
  end

  it 'still renders the flash container the messages land in' do
    get list_path(list)

    expect(response.body.scan('id="flash"').count).to eq(1)
  end
end
