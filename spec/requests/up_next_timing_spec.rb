# frozen_string_literal: true

require 'rails_helper'

# When the up-next card appears, and how long it then counts for. One number does both, so
# the countdown reaches zero as the film does rather than at a moment of its own -- and it
# is a setting rather than a constant in the player controller, so the page has to carry it.
RSpec.describe 'Up next timing', :needs_provider do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, auto_next: true) }
  let(:entry) { create(:entry, list: list, name: 'Gladiator', length: 155) }

  before { sign_in user }

  it 'hands the player the configured lead' do
    AppSetting.update_up_next_lead!(45)

    get watch_entry_path(entry)

    expect(response.body).to include('data-player-progress-up-next-lead-value="45"')
  end

  it 'hands it the default when nobody has changed it' do
    get watch_entry_path(entry)

    expect(response.body).to include('data-player-progress-up-next-lead-value="15"')
  end

  # The same number on the card, so the count and the lead cannot disagree.
  it 'counts down for as long as the lead that raised it' do
    AppSetting.update_up_next_lead!(45)

    get watch_entry_path(entry)

    expect(response.body).to include('data-auto-advance-seconds-value="45"')
    expect(response.body).to include('<strong data-auto-advance-target="countdown">45</strong>')
  end

  describe 'where the mark actually falls' do
    let(:setting) { AppSetting.current }

    it 'is the lead before the end of anything of normal length' do
      # A 155-minute film: fifteen seconds before the end, with room to spare.
      expect(setting.up_next_mark_for(155 * 60)).to eq(155 * 60 - 15)
      expect(setting.up_next_seconds_before_end(155)).to eq(15)
    end

    # Both routes to the card are gated on the film counting as watched, so a mark earlier
    # than that is a card that never appears. Fifteen seconds before the end of a
    # two-minute clip is exactly that.
    it 'is pulled back to the completion mark on something short enough' do
      expect(setting.up_next_mark_for(120)).to eq(120 * UserEntry::COMPLETION_FRACTION)
      expect(setting.up_next_seconds_before_end(2)).to eq(6)
    end

    it 'has nothing to say about a film with no runtime' do
      expect(setting.up_next_mark_for(0)).to be_nil
      expect(setting.up_next_seconds_before_end(0)).to eq(0)
    end
  end
end
