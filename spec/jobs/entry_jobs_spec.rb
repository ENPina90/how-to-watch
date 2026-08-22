require 'rails_helper'

# These cover the contract the Sidekiq switch depends on: entry callbacks enqueue work
# rather than doing it inline, and a job whose record disappeared before it ran is
# dropped instead of failing (and burning Sidekiq's retry schedule).
RSpec.describe 'Entry background jobs', type: :job do
  include ActiveJob::TestHelper

  let(:list) { create(:list) }

  describe 'enqueueing' do
    it 'checks the source of a newly created entry in the background' do
      expect {
        create(:entry, list: list, source: 'https://example.com/embed/tt0848228')
      }.to have_enqueued_job(CheckEntrySourceJob)
    end

    it 'attaches the poster in the background when a pic URL is present' do
      expect {
        create(:entry, list: list, pic: 'https://example.com/poster.jpg')
      }.to have_enqueued_job(AttachPosterFromPicJob)
    end

    it 'checks the source even when the legacy column is empty' do
      # The URL is computed from the provider template now, so there is no column to
      # gate the check on; the job no-ops if nothing resolves.
      expect {
        create(:entry, list: list, source: nil)
      }.to have_enqueued_job(CheckEntrySourceJob)
    end
  end

  describe 'when the entry is deleted before the job runs' do
    it 'discards the job instead of raising' do
      entry = create(:entry, list: list, source: 'https://example.com/embed/tt0848228')
      clear_enqueued_jobs

      CheckEntrySourceJob.perform_later(entry)
      entry.destroy

      expect { perform_enqueued_jobs }.not_to raise_error
    end
  end
end
