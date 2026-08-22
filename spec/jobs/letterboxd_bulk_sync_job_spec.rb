require 'rails_helper'

RSpec.describe LetterboxdBulkSyncJob do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before do
    # The job paces itself for Letterboxd's rate limit; no need to actually wait here.
    allow_any_instance_of(described_class).to receive(:sleep)
  end

  it 'syncs every completed entry' do
    watched = create(:entry, list: list, name: 'Watched', position: 1)
    unwatched = create(:entry, list: list, name: 'Unwatched', position: 2)
    watched.mark_completed_by!(user)

    allow(user).to receive(:letterboxd_connected?).and_return(true)
    allow(User).to receive(:find_by).with(id: user.id).and_return(user)
    allow(user).to receive(:sync_entry_to_letterboxd!).and_return({ error: false, message: 'ok' })

    described_class.perform_now(user.id)

    expect(user).to have_received(:sync_entry_to_letterboxd!).with(watched).once
    expect(user).not_to have_received(:sync_entry_to_letterboxd!).with(unwatched)
  end

  it 'keeps going when one entry fails' do
    first = create(:entry, list: list, name: 'One', position: 1)
    second = create(:entry, list: list, name: 'Two', position: 2)
    [first, second].each { |e| e.mark_completed_by!(user) }

    allow(user).to receive(:letterboxd_connected?).and_return(true)
    allow(User).to receive(:find_by).with(id: user.id).and_return(user)
    allow(user).to receive(:sync_entry_to_letterboxd!).and_return({ error: true, message: 'rejected' })

    expect { described_class.perform_now(user.id) }.not_to raise_error
    expect(user).to have_received(:sync_entry_to_letterboxd!).twice
  end

  it 'does nothing when the account is not connected' do
    entry = create(:entry, list: list, position: 1)
    entry.mark_completed_by!(user)

    allow(User).to receive(:find_by).with(id: user.id).and_return(user)
    allow(user).to receive(:letterboxd_connected?).and_return(false)
    allow(user).to receive(:sync_entry_to_letterboxd!)

    described_class.perform_now(user.id)

    expect(user).not_to have_received(:sync_entry_to_letterboxd!)
  end

  it 'does not raise for a deleted user' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
