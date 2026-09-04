# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SourceCatalog do
  let(:first_declared) { described_class::PROVIDERS.first }

  describe '.sync!' do
    it 'creates every provider the app ships with on an empty database' do
      result = described_class.sync!

      expect(Source.pluck(:slug)).to match_array(described_class::PROVIDERS.map { |p| p[:slug] })
      expect(result.created.size).to eq(described_class::PROVIDERS.size)
      expect(result.failed).to be_empty
    end

    it 'numbers a fresh database in the order the list declares' do
      described_class.sync!

      expect(Source.order(:position).pluck(:slug))
        .to eq(described_class::PROVIDERS.map { |p| p[:slug] })
    end

    # It runs on every boot, so running it twice has to be uneventful.
    it 'adds nothing the second time' do
      described_class.sync!

      expect { described_class.sync! }.not_to change(Source, :count)
    end

    describe 'what it refuses to touch' do
      before { described_class.sync! }

      # A deploy must not undo an edit made through the admin UI -- that is where a
      # provider's URL shape gets fixed when it changes.
      it 'leaves an edited template alone' do
        source = Source.find_by(slug: first_declared[:slug])
        source.update!(templates: { 'movie' => 'https://edited.test/%{imdb}' })

        described_class.sync!

        expect(source.reload.templates).to eq({ 'movie' => 'https://edited.test/%{imdb}' })
      end

      it 'leaves a deactivated provider deactivated' do
        source = Source.find_by(slug: first_declared[:slug])
        source.update!(active: false)

        described_class.sync!

        expect(source.reload).not_to be_active
      end

      # The order is dragged into place on /sources; a deploy reshuffling it would undo
      # somebody's decision about what channels fall back to.
      it 'leaves an order somebody set alone' do
        reversed = Source.order(position: :desc).pluck(:id)
        Source.reorder!(reversed)
        before = Source.order(:position).pluck(:slug)

        described_class.sync!

        expect(Source.order(:position).pluck(:slug)).to eq(before)
      end
    end

    describe 'adding a provider to a database that already has some' do
      # This is the bug that had to be fixed by hand in production: a new provider carrying
      # a position from the list collided with rows already holding those numbers, leaving
      # the fallback ambiguous.
      it 'appends it rather than colliding with positions already in use' do
        described_class.sync!
        Source.find_by(slug: first_declared[:slug]).destroy!
        highest = Source.maximum(:position)

        described_class.sync!

        expect(Source.find_by(slug: first_declared[:slug]).position).to eq(highest + 1)
        expect(Source.pluck(:position).uniq.size).to eq(Source.count)
      end

      # A new provider landing at the top would silently become what channels fall back to.
      it 'does not make a new provider the fallback' do
        described_class.sync!
        fallback = Source.active.where(kind: 'imdb').order(:position).first
        Source.find_by(slug: 'vidsrc2').destroy!

        described_class.sync!

        expect(Source.active.where(kind: 'imdb').order(:position).first).to eq(fallback)
      end
    end

    # Two web instances booting together both try to create the same provider.
    it 'treats losing a race to another booting instance as success' do
      allow(Source).to receive(:exists?).and_return(false)
      allow(Source).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new('taken'))

      result = described_class.sync!

      expect(result.failed).to be_empty
      expect(result.kept.size).to eq(described_class::PROVIDERS.size)
    end

    # It runs during boot, so it reports a failure rather than refusing to start.
    it 'records a provider it could not create instead of raising' do
      allow(Source).to receive(:exists?).and_return(false)
      allow(Source).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Source.new))

      expect { described_class.sync! }.not_to raise_error
      expect(described_class.sync!.failed.size).to eq(described_class::PROVIDERS.size)
    end
  end

  describe '.missing' do
    it 'names what the database has never heard of' do
      described_class.sync!
      Source.find_by(slug: first_declared[:slug]).destroy!

      expect(described_class.missing).to eq([first_declared[:slug]])
    end

    it 'is empty once everything is present' do
      described_class.sync!

      expect(described_class.missing).to be_empty
    end
  end

  describe '.drift' do
    before { described_class.sync! }

    it 'is silent when the database matches what is shipped' do
      expect(described_class.drift).to be_empty
    end

    it 'reports an edited template, and what both sides say' do
      Source.find_by(slug: first_declared[:slug])
            .update!(templates: { 'movie' => 'https://edited.test/%{imdb}' })

      entry = described_class.drift.find { |d| d[:slug] == first_declared[:slug] }

      expect(entry[:differences]).to have_key(:templates)
      expect(entry[:differences][:templates][:actual]).to eq({ 'movie' => 'https://edited.test/%{imdb}' })
    end

    it 'reports a provider switched off in the database' do
      Source.find_by(slug: first_declared[:slug]).update!(active: false)

      entry = described_class.drift.find { |d| d[:slug] == first_declared[:slug] }

      expect(entry[:differences][:active]).to eq({ declared: true, actual: false })
    end

    # Order and expiry are the admin's, not the list's, so they are not drift.
    it 'does not treat a reordered or renewed provider as drift' do
      Source.reorder!(Source.order(position: :desc).pluck(:id))
      Source.find_by(slug: first_declared[:slug]).renew!

      expect(described_class.drift).to be_empty
    end
  end
end
