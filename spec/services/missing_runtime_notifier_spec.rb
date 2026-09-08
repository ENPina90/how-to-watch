# frozen_string_literal: true

require 'rails_helper'

# `entries.length` is what the cable schedule lays a day out from. Where it is missing the
# schedule guesses, and a guess that overshoots the real file leaves the slot outlasting the
# programme -- at which point the player, handed a start position past the end, begins the
# whole thing again. These are the warnings that make that visible before somebody meets it.
RSpec.describe MissingRuntimeNotifier do
  let!(:admin) { create(:user, :admin) }
  let(:channel) { create(:list, name: 'Annals', default: true) }

  def scheduled(name, length, position: 1)
    create(:entry, list: channel, name: name, media: 'episode', length: length, position: position)
  end

  describe 'what it warns about' do
    it 'raises one warning per scheduled entry with no runtime' do
      scheduled('No Runtime', nil, position: 1)
      scheduled('Also None', 0, position: 2)
      scheduled('Fine', 24, position: 3)

      expect { described_class.call }.to change(Notification, :count).by(2)
      expect(Notification.pluck(:kind).uniq).to eq([Notification::MISSING_RUNTIME])
    end

    it 'names the channel it is scheduled on and the length being assumed' do
      entry = scheduled('No Runtime', nil)

      described_class.call
      data = Notification.find_by(subject: entry).data

      expect(data['name']).to eq('No Runtime')
      expect(data['channel']).to eq('Annals')
      expect(data['guess']).to eq(CableSchedule.fallback_minutes(entry))
    end

    # A missing runtime off the dial is untidy; on a channel that plays to a clock it is a
    # programme that will misbehave. Four hundred warnings nobody reads would bury the
    # twenty that matter.
    it 'ignores entries on channels that are not on the dial' do
      elsewhere = create(:list, name: 'Private', default: false)
      create(:entry, list: elsewhere, name: 'Off Dial', media: 'episode', length: nil)

      expect { described_class.call }.not_to change(Notification, :count)
    end

    it 'warns every admin, and nobody else' do
      create(:user, :admin)
      create(:user)
      scheduled('No Runtime', nil)

      described_class.call

      expect(Notification.count).to eq(2)
      expect(Notification.pluck(:user_id).uniq.sort).to eq(User.where(admin: true).ids.sort)
    end
  end

  describe 'reconciling' do
    it 'raises nothing twice for the same entry' do
      scheduled('No Runtime', nil)
      described_class.call

      expect { described_class.call }.not_to change(Notification, :count)
    end

    # Filling the runtime in is the fix, and it should clear the card without anybody
    # having to dismiss it.
    it 'retires the warning once the runtime is filled in' do
      entry = scheduled('No Runtime', nil)
      described_class.call

      entry.update!(length: 24)

      expect { described_class.call }.to change(Notification, :count).by(-1)
    end

    it 'retires the warning when the channel comes off the dial' do
      scheduled('No Runtime', nil)
      described_class.call

      channel.update!(default: false)

      expect { described_class.call }.to change(Notification, :count).by(-1)
    end

    # Dismissal is permanent for a given row, so losing the runtime again has to read as a
    # new warning rather than a dismissed one.
    it 'raises it again if the runtime is lost after being fixed' do
      entry = scheduled('No Runtime', nil)
      described_class.call
      entry.update!(length: 24)
      described_class.call

      entry.update!(length: nil)

      expect { described_class.call }.to change(Notification, :count).by(1)
    end

    it 'clears warnings held by an account that is no longer an admin' do
      scheduled('No Runtime', nil)
      described_class.call

      admin.update!(admin: false)

      expect { described_class.call }.to change(Notification, :count).by(-1)
    end
  end

  # An entry lent to a second channel is one problem, not two.
  it 'counts a borrowed entry once' do
    borrower = create(:list, name: 'Borrower', default: true)
    entry = scheduled('No Runtime', nil)
    ListRelationship.create!(parent_list: borrower, child_list: channel, position: 1)

    described_class.call

    expect(Notification.where(subject: entry).count).to eq(1)
  end

  it 'reports what it did' do
    scheduled('No Runtime', nil)
    scheduled('Fine', 24, position: 2)

    result = described_class.call

    expect(result.checked).to eq(2)
    expect(result.missing).to eq(1)
    expect(result.created).to eq(1)
  end
end
