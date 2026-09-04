# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LetterboxdSyncJob do
  let(:body) { Rails.root.join('spec/fixtures/letterboxd/diary.xml').read }

  before do
    stub_request(:get, %r{letterboxd\.com/.+/rss/}).to_return(status: 200, body: body)
    stub_request(:get, %r{api\.themoviedb\.org}).to_return(status: 200, body: { imdb_id: 'tt1' }.to_json)
    # Details are LetterboxdList's business; here it only matters that the sync survives
    # OMDb having nothing for the film.
    stub_request(:get, %r{omdbapi\.com}).to_return(status: 200, body: { Response: 'False' }.to_json)
  end

  it 'fills the channel for a linked member' do
    user = create(:user, username: 'testmember', letterboxd_enabled: true)

    described_class.perform_now(user.id)

    expect(user.lists.find_by(letterboxd: true).entries.count).to eq(3)
  end

  it 'does nothing for a member who has since unlinked' do
    user = create(:user, username: 'testmember')

    expect { described_class.perform_now(user.id) }.not_to change { List.count }
  end

  it 'does nothing for a user who no longer exists' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  # A private profile or a Letterboxd outage. Retrying would hammer a feed that is
  # deliberately unreadable, and the weekly run will try again anyway.
  it 'gives up quietly when the diary cannot be read' do
    user = create(:user, username: 'testmember', letterboxd_enabled: true)
    stub_request(:get, %r{letterboxd\.com/.+/rss/}).to_return(status: 403, body: '')

    expect { described_class.perform_now(user.id) }.not_to raise_error
  end

  describe 'what it records for the profile page to report' do
    let(:user) { create(:user, username: 'testmember', letterboxd_enabled: true) }

    it 'marks a success, so the page can stop saying it is still working' do
      described_class.perform_now(user.id)

      expect(user.reload.letterboxd_synced_at).to be_present
      expect(user.letterboxd_sync_error).to be_nil
      expect(user.letterboxd_sync_state).to eq(:ok)
    end

    it 'keeps the reason a diary could not be read' do
      stub_request(:get, %r{letterboxd\.com/.+/rss/}).to_return(status: 403, body: '')

      described_class.perform_now(user.id)

      expect(user.reload.letterboxd_sync_error).to include('403')
      expect(user.letterboxd_sync_state).to eq(:failed)
    end

    # Silence is the failure mode this whole column exists to prevent, so an unexpected
    # error is recorded and then re-raised for the queue to retry and report.
    it 'records an unexpected failure and still raises it' do
      allow_any_instance_of(LetterboxdList).to receive(:sync!).and_raise(ActiveRecord::RecordInvalid)

      expect { described_class.perform_now(user.id) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(user.reload.letterboxd_sync_state).to eq(:failed)
    end

    # Recording the outcome must not look like a settings change, or it would queue
    # another sync and arrive straight back here.
    it 'does not queue another sync by recording the outcome' do
      described_class.perform_now(user.id)

      expect { described_class.perform_now(user.id) }.not_to have_enqueued_job(described_class)
    end

    it 'reads as still working before the job has run' do
      expect(user.letterboxd_sync_state).to eq(:waiting)
    end
  end
end

RSpec.describe LetterboxdWeeklyRefreshJob do
  it 'queues a sync for every linked member' do
    linked = create(:user, username: 'testmember', letterboxd_enabled: true)
    create(:user, username: 'someone')

    expect { described_class.perform_now }
      .to have_enqueued_job(LetterboxdSyncJob).with(linked.id).exactly(:once)
  end

  # An account can carry the flag but have lost the username the diary is read from.
  it 'skips a linked member with no username left to read' do
    user = create(:user, username: 'testmember', letterboxd_enabled: true)
    user.update_columns(username: nil)

    expect { described_class.perform_now }.not_to have_enqueued_job(LetterboxdSyncJob)
  end

  it 'spreads the syncs out rather than firing them all at once' do
    3.times { |i| create(:user, username: "member#{i}", letterboxd_enabled: true) }
    # Opting in queues a sync of its own; this is about what the weekly run adds.
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.perform_now

    queued = ActiveJob::Base.queue_adapter.enqueued_jobs
                            .select { |job| job[:job] == LetterboxdSyncJob }
    gaps = queued.map { |job| job[:at] }.sort.each_cons(2).map { |a, b| (b - a).round }

    expect(queued.size).to eq(3)
    expect(gaps).to all(eq(described_class::STAGGER.to_i))
  end
end
