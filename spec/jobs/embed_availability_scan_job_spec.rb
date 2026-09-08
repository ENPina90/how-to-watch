# frozen_string_literal: true

require 'rails_helper'

# The sweep itself: one trip to VidSrc, then both things that come of it -- the entry wears
# the same mark the "report broken link" button leaves, and the admin gets told.
RSpec.describe EmbedAvailabilityScanJob do
  let!(:admin) { create(:user, :admin) }
  let(:list) { create(:list, name: 'Planet(s)') }
  let(:entry) { create(:entry, list: list, name: 'Alien Earths', imdb: 'tt1517549', stream: true) }

  def row(for_entry)
    EmbedAvailabilityAudit::Row.new(
      entry: for_entry,
      lookup: VidsrcAvailability::Lookup.new(type: 'movie', imdb: for_entry.imdb),
      reason: 'VidSrc has no file for it'
    )
  end

  def audit_finds(rows, checked: 1)
    allow(EmbedAvailabilityAudit).to receive(:call).and_return(
      EmbedAvailabilityAudit::Result.new(checked: checked, suspected: rows.size, missing: rows,
                                         unknown: [], skipped: 0)
    )
  end

  it 'marks an unplayable entry the way the report button does' do
    audit_finds([row(entry)])

    described_class.perform_now

    expect(entry.reload.stream).to be(false)
  end

  it 'raises a notification for it as well' do
    audit_finds([row(entry)])

    described_class.perform_now

    expect(Notification.where(user: admin, kind: Notification::UNPLAYABLE_EMBED).count).to eq(1)
  end

  # The notification retires on its own when VidSrc picks the title back up. The mark does
  # not: taking it off would also take it off every entry somebody reported by hand, for a
  # reason this job cannot see.
  it 'never clears the mark, only sets it' do
    reported = create(:entry, list: list, name: 'Reported by hand', imdb: 'tt0172495', stream: false)
    audit_finds([])

    described_class.perform_now

    expect(reported.reload.stream).to be(false)
  end

  it 'leaves a playable entry alone' do
    audit_finds([])

    described_class.perform_now

    expect(entry.reload.stream).to be(true)
    expect(Notification.where(kind: Notification::UNPLAYABLE_EMBED)).to be_empty
  end

  # If VidSrc cannot be asked, every entry looks unplayable. Marking the catalogue broken on
  # the strength of that would be a great deal worse than doing nothing.
  it 'marks and says nothing when the check cannot be trusted to run' do
    allow(EmbedAvailabilityAudit).to receive(:call)
      .and_raise(EmbedAvailabilityAudit::CannotCheck, 'the VidSrc data API is not answering')

    expect { described_class.perform_now }.not_to raise_error

    expect(entry.reload.stream).to be(true)
    expect(Notification.where(kind: Notification::UNPLAYABLE_EMBED)).to be_empty
  end
end
