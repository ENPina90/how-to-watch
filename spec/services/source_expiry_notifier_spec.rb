# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SourceExpiryNotifier do
  let!(:admin) { create(:user, :admin) }

  def source(slug:, valid_until:, active: true)
    Source.create!(name: slug.titleize, slug: slug, kind: 'imdb', active: active,
                   position: 1, valid_until: valid_until,
                   templates: { 'movie' => "https://#{slug}.test/embed/movie?imdb=%{imdb}" })
  end

  def warnings_for(user) = Notification.where(user: user, kind: Notification::SOURCE_EXPIRING)

  describe 'what it warns about' do
    # The scan's own job, as opposed to the callback's: a provider nobody has touched
    # drifts into the window because a day passed. update_column to move the date without
    # firing the callback, which is what the passage of time looks like from here.
    it 'warns when a provider drifts into the window with nothing else changing' do
      drifting = source(slug: 'soon', valid_until: 300.days.from_now.to_date)
      drifting.update_column(:valid_until, 10.days.from_now.to_date)

      expect { described_class.call }.to change { warnings_for(admin).count }.by(1)
    end

    # The case the whole thing exists for: one that lapsed while nobody was looking.
    it 'warns about a provider that has already expired' do
      source(slug: 'gone', valid_until: 5.days.ago.to_date)

      described_class.call

      expect(warnings_for(admin).count).to eq(1)
    end

    it 'says nothing about a provider that is a long way off' do
      source(slug: 'fine', valid_until: 300.days.from_now.to_date)

      described_class.call

      expect(warnings_for(admin)).to be_empty
    end

    it 'says nothing about a provider that cannot lapse' do
      Source.create!(name: 'MEGA', slug: 'mega', kind: 'direct', active: true, position: 9,
                     templates: { 'default' => 'https://mega.nz/embed/%{source_key}' })

      described_class.call

      expect(warnings_for(admin)).to be_empty
    end

    # Nothing plays through a deactivated provider, so its address lapsing is not a problem.
    it 'says nothing about a deactivated provider, however overdue' do
      source(slug: 'off', valid_until: 30.days.ago.to_date, active: false)

      described_class.call

      expect(warnings_for(admin)).to be_empty
    end
  end

  describe 'who it warns' do
    it 'warns every admin' do
      second = create(:user, :admin)
      source(slug: 'soon', valid_until: 3.days.from_now.to_date)

      described_class.call

      expect(warnings_for(second).count).to eq(1)
    end

    it 'does not warn an ordinary member' do
      member = create(:user)
      source(slug: 'soon', valid_until: 3.days.from_now.to_date)

      described_class.call

      expect(warnings_for(member)).to be_empty
    end

    # An account that loses its admin flag should stop carrying admin-only rows around.
    it 'takes warnings back off somebody who is no longer an admin' do
      source(slug: 'soon', valid_until: 3.days.from_now.to_date)
      described_class.call
      admin.update!(admin: false)

      described_class.call

      expect(warnings_for(admin)).to be_empty
    end
  end

  describe 'running more than once' do
    it 'does not stack up a copy per run' do
      source(slug: 'soon', valid_until: 3.days.from_now.to_date)

      3.times { described_class.call }

      expect(warnings_for(admin).count).to eq(1)
    end

    it 'writes nothing at all when there is nothing to say' do
      source(slug: 'fine', valid_until: 300.days.from_now.to_date)

      expect(described_class.call).to have_attributes(created: 0, removed: 0)
    end

    # Renewing is the answer to the warning, so it has to clear it without anyone
    # dismissing anything.
    it 'retires the warning once the provider is renewed' do
      soon = source(slug: 'soon', valid_until: 3.days.from_now.to_date)
      described_class.call

      soon.renew!
      described_class.call

      expect(warnings_for(admin)).to be_empty
    end

    it 'retires the warning when the provider is switched off instead' do
      soon = source(slug: 'soon', valid_until: 3.days.from_now.to_date)
      described_class.call

      soon.update!(active: false)
      described_class.call

      expect(warnings_for(admin)).to be_empty
    end

    # A warning is about a state rather than an event, so dismissing it must not be
    # permanent silence -- but it must hold for the date it was about.
    it 'leaves a dismissed warning dismissed while the date is unchanged' do
      source(slug: 'soon', valid_until: 3.days.from_now.to_date)
      described_class.call
      warnings_for(admin).first.dismiss!

      described_class.call

      expect(warnings_for(admin).count).to eq(1)
      expect(warnings_for(admin).first).to be_dismissed
    end

    # ...and once the date moves, it is a different warning, so a past dismissal of the
    # old one says nothing about the new one.
    it 'warns again when the date moves and the new date is still close' do
      soon = source(slug: 'soon', valid_until: 3.days.from_now.to_date)
      described_class.call
      warnings_for(admin).first.dismiss!

      soon.update!(valid_until: 10.days.from_now.to_date)
      described_class.call

      expect(warnings_for(admin).active.count).to eq(1)
    end
  end

  # Saving a source recomputes its own warnings, so the page is right the moment you act
  # on it rather than after the next nightly scan.
  describe 'when a source is saved' do
    it 'raises the warning without waiting for the scan' do
      expect { source(slug: 'soon', valid_until: 3.days.from_now.to_date) }
        .to change { warnings_for(admin).count }.by(1)
    end

    it 'clears the warning as soon as it is renewed' do
      soon = source(slug: 'soon', valid_until: 3.days.from_now.to_date)

      expect { soon.renew! }.to change { warnings_for(admin).count }.from(1).to(0)
    end
  end

  it 'keeps enough on the row to describe a provider that has since been deleted' do
    source(slug: 'soon', valid_until: 3.days.from_now.to_date)
    described_class.call

    expect(warnings_for(admin).first.data)
      .to include('slug' => 'soon', 'valid_until' => 3.days.from_now.to_date.to_s)
  end
end
