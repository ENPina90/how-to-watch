# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DeploymentStatus do
  subject(:status) { described_class.new }

  # Neither Redis nor a Sidekiq process exists in the test environment, which is the same
  # shape as production with the queue down -- the case this class exists to report.
  def stub_worker(sha:, booted_at: Time.current)
    allow(Sidekiq).to receive(:redis).and_return({ sha: sha, booted_at: booted_at.iso8601 }.to_json)
  end

  def stub_processes(beats)
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(beats.map { |beat| { 'beat' => beat.to_f } })
  end

  before { allow(ENV).to receive(:[]).and_call_original }

  describe '#drift?' do
    it 'is true when the two builds differ' do
      allow(ENV).to receive(:[]).with('RAILWAY_GIT_COMMIT_SHA').and_return('aaaaaaa1')
      stub_worker(sha: 'bbbbbbb2')

      expect(status).to be_drift
    end

    it 'is false when they match' do
      allow(ENV).to receive(:[]).with('RAILWAY_GIT_COMMIT_SHA').and_return('aaaaaaa1')
      stub_worker(sha: 'aaaaaaa1')

      expect(status).not_to be_drift
    end

    # An unknown sha is no information, not a mismatch. Claiming drift here would cry wolf
    # on every local run, where Railway injects nothing.
    it 'is false when either side is unknown' do
      allow(ENV).to receive(:[]).with('RAILWAY_GIT_COMMIT_SHA').and_return(nil)
      stub_worker(sha: 'bbbbbbb2')

      expect(status).not_to be_drift
      expect(status).not_to be_unknown
    end

    it 'reports knowing nothing when neither side reports' do
      allow(ENV).to receive(:[]).with('RAILWAY_GIT_COMMIT_SHA').and_return(nil)
      allow(Sidekiq).to receive(:redis).and_return(nil)

      expect(status).to be_unknown
    end
  end

  describe 'liveness' do
    it 'reads the heartbeat from Sidekiq own process registry' do
      stub_processes([3.seconds.ago])

      expect(status).to be_worker_running
      expect(status).not_to be_stale
    end

    it 'calls a worker stale once it stops reporting in' do
      stub_processes([10.minutes.ago])

      expect(status).to be_worker_running
      expect(status).to be_stale
    end

    it 'reports no worker at all when the registry is empty' do
      stub_processes([])

      expect(status).not_to be_worker_running
      expect(status).to be_stale
    end
  end

  # A dashboard is not worth a 500 when the queue is down, and being down is exactly what
  # it is there to show.
  describe 'when Redis cannot be reached' do
    before { allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError) }

    it 'reports an unknown worker rather than raising' do
      expect { status.worker_sha }.not_to raise_error
      expect(status.worker_sha).to be_nil
      expect(status.worker_booted_at).to be_nil
    end

    it 'swallows the failure when recording, so it cannot stop the worker booting' do
      expect { described_class.record_worker! }.not_to raise_error
    end
  end

  describe '.record_worker!' do
    it 'writes the running build and the time it booted' do
      allow(ENV).to receive(:[]).with('RAILWAY_GIT_COMMIT_SHA').and_return('aaaaaaa1')
      redis = instance_double(Redis)
      allow(Sidekiq).to receive(:redis).and_yield(redis)

      expect(redis).to receive(:set) do |key, payload|
        expect(key).to eq(described_class::KEY)
        expect(JSON.parse(payload)).to include('sha' => 'aaaaaaa1', 'booted_at' => be_present)
      end

      described_class.record_worker!
    end
  end

  describe '#short' do
    it 'trims a sha to something readable' do
      expect(status.short('a16990d5f3c2b1')).to eq('a16990d')
      expect(status.short(nil)).to be_nil
    end
  end
end
