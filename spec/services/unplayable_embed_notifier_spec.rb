# frozen_string_literal: true

require 'rails_helper'

# Same shape as the poster warnings: a state, reconciled each run, so a title VidSrc
# acquires later stops being reported without anyone dismissing it.
RSpec.describe UnplayableEmbedNotifier do
  let!(:admin) { create(:user, :admin) }
  let(:list) { create(:list, name: 'Planet(s)') }
  let(:entry) { create(:entry, list: list, name: 'Alien Earths', imdb: 'tt1517549') }

  def row(for_entry = entry)
    EmbedAvailabilityAudit::Row.new(
      entry: for_entry,
      lookup: VidsrcAvailability::Lookup.new(type: 'movie', imdb: for_entry.imdb),
      reason: 'VidSrc has no file for it'
    )
  end


  def notices_for(user) = Notification.where(user: user, kind: Notification::UNPLAYABLE_EMBED)

  it 'raises one notification per unplayable entry, pointed at it' do
    described_class.new(missing: [row]).call

    expect(notices_for(admin).count).to eq(1)
    expect(notices_for(admin).first.subject).to eq(entry)
    expect(notices_for(admin).first.data).to include('name' => 'Alien Earths', 'imdb' => 'tt1517549')
  end

  it 'retires the notification once VidSrc has the title' do
    described_class.new(missing: [row]).call

    expect { described_class.new(missing: []).call }
      .to change { notices_for(admin).count }.from(1).to(0)
  end

  it 'leaves a dismissed one dismissed while the entry still asks for the same thing' do
    described_class.new(missing: [row]).call
    notices_for(admin).first.dismiss!

    described_class.new(missing: [row]).call

    expect(notices_for(admin).active).to be_empty
    expect(notices_for(admin).count).to eq(1)
  end

  # Dismissing hides this entry as it stands. Pointing it at a different id is a new
  # question, and one worth being told the answer to.
  it 'raises a fresh one when the entry is pointed at a different id' do
    described_class.new(missing: [row]).call
    notices_for(admin).first.dismiss!

    entry.update!(imdb: 'tt9999999')
    described_class.new(missing: [row]).call

    expect(notices_for(admin).active.count).to eq(1)
  end

  it 'tells nobody but the admins' do
    member = create(:user)

    described_class.new(missing: [row]).call

    expect(notices_for(member)).to be_empty
  end
end
