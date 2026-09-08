# frozen_string_literal: true

require 'rails_helper'

# The player has to be told when the card appears, because it is a setting now rather than
# a constant in the controller.
RSpec.describe 'Up next timing', :needs_provider do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list, name: 'Gladiator', length: 155) }

  before { sign_in user }

  it 'hands the player the configured mark' do
    AppSetting.update_up_next_percent!(99)

    get watch_entry_path(entry)

    expect(response.body).to include('data-player-progress-credits-value="0.99"')
  end

  it 'hands it the default when nobody has changed it' do
    get watch_entry_path(entry)

    expect(response.body).to include('data-player-progress-credits-value="0.98"')
  end
end
