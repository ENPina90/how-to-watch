# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notification do
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }

  def build_one(user:, kind: Notification::SOURCE_EXPIRING, key: SecureRandom.hex(4))
    described_class.create!(user: user, kind: kind, dedupe_key: key)
  end

  describe '.visible_to' do
    it 'shows a member their own notifications' do
      mine = build_one(user: member, kind: 'list_subscribed')
      build_one(user: admin, kind: 'list_subscribed')

      expect(described_class.visible_to(member)).to contain_exactly(mine)
    end

    # The notifier only writes these for admins, but an account can lose the flag after the
    # row exists -- so the read side checks too rather than trusting the write side.
    it 'hides an admin-only kind from someone who is no longer an admin' do
      build_one(user: member)

      expect(described_class.visible_to(member)).to be_empty
    end

    it 'shows an admin-only kind to an admin' do
      warning = build_one(user: admin)

      expect(described_class.visible_to(admin)).to contain_exactly(warning)
    end
  end

  describe '#dismiss!' do
    it 'takes it off the active list without deleting it' do
      notification = build_one(user: admin)

      notification.dismiss!

      expect(notification).to be_dismissed
      expect(described_class.active).to be_empty
      expect(described_class.count).to eq(1)
    end

    it 'leaves the original dismissal time alone when called twice' do
      notification = build_one(user: admin)
      notification.dismiss!
      first = notification.reload.dismissed_at

      notification.dismiss!

      # Exact equality, not a tolerance: a second write would land a different timestamp
      # even microseconds later.
      expect(notification.reload.dismissed_at).to eq(first)
    end
  end

  # What stops the daily scan from writing a fresh copy every morning.
  it 'refuses a second notification with the same key for one person' do
    build_one(user: admin, key: 'source_expiring:1:2026-01-01')

    expect { build_one(user: admin, key: 'source_expiring:1:2026-01-01') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'lets two people each have their own copy of the same warning' do
    build_one(user: admin, key: 'source_expiring:1:2026-01-01')
    second_admin = create(:user, :admin)

    expect { build_one(user: second_admin, key: 'source_expiring:1:2026-01-01') }
      .not_to raise_error
  end
end
