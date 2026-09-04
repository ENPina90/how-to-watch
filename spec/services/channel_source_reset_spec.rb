# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChannelSourceReset do
  let(:user) { create(:user) }

  let(:target) do
    Source.create!(name: 'Player', slug: 'framerelay', kind: 'imdb', active: true, position: 1,
                   templates: { 'movie' => 'https://framerelay.dev/embed/movie?imdb=%{imdb}' })
  end

  let(:other_imdb) do
    Source.create!(name: 'VidSrc 2', slug: 'vidsrc2', kind: 'imdb', active: true, position: 2,
                   templates: { 'movie' => 'https://vidsrc2.ru/embed/movie?imdb=%{imdb}' })
  end

  # The case this exists for: a channel stranded on a provider that has been switched off.
  let(:dead_imdb) do
    Source.create!(name: 'VidSrc.cc', slug: 'vidsrc-cc', kind: 'imdb', active: false, position: 3,
                   templates: { 'movie' => 'https://vidsrc.cc/v3/embed/movie/%{imdb}' })
  end

  let(:drive) do
    Source.create!(name: 'Google Drive', slug: 'google-drive', kind: 'direct', active: true, position: 9,
                   templates: { 'default' => 'https://drive.google.com/file/d/%{source_key}/preview' })
  end

  describe 'the channels it moves' do
    it 'points a channel on another imdb provider at the target' do
      channel = create(:list, user: user, provider: other_imdb)

      described_class.call(target)

      expect(channel.reload.provider).to eq(target)
    end

    # Being on a dead provider is the situation this is meant to rescue.
    it 'rescues a channel stranded on a deactivated provider' do
      channel = create(:list, user: user, provider: dead_imdb)

      described_class.call(target)

      expect(channel.reload.provider).to eq(target)
    end

    # No provider is not a choice anyone made -- it falls through to whichever active
    # provider sorts first. Naming it is the point of the button.
    it 'gives a channel with no provider an explicit one' do
      channel = create(:list, user: user, provider: nil)

      described_class.call(target)

      expect(channel.reload.provider).to eq(target)
    end

    # A direct provider addresses a file by a key that means nothing anywhere else, so
    # moving it produces a dead link rather than a different player.
    it 'leaves a channel on a direct provider alone' do
      channel = create(:list, user: user, provider: drive)

      described_class.call(target)

      expect(channel.reload.provider).to eq(drive)
    end

    it 'reports how many channels it moved' do
      create(:list, user: user, provider: other_imdb)
      create(:list, user: user, provider: nil)
      create(:list, user: user, provider: drive)
      # Creating a user brings a channel of its own, so count what is eligible rather than
      # assuming only the three above exist. Counted by subtraction on purpose: `where.not`
      # compiles to `provider_id != x`, which is never true for NULL and would quietly drop
      # every channel that has no provider -- the same trap the service avoids.
      eligible = List.count - List.where(provider: drive).count

      expect(described_class.call(target).channels).to eq(eligible)
    end
  end

  describe 'the entry overrides it clears' do
    let(:channel) { create(:list, user: user, provider: other_imdb) }

    # An entry's own provider beats its channel's, so leaving these would make the reset a
    # lie for exactly the entries somebody had bothered to pin.
    it 'clears an entry pinned to another imdb provider, so it follows its channel' do
      entry = create(:entry, list: channel, media: 'movie', imdb: 'tt0111161', provider: other_imdb)

      described_class.call(target)

      expect(entry.reload.provider).to be_nil
      expect(entry.resolved_source).to eq(target)
    end

    it 'leaves an entry on a direct provider alone, key and all' do
      entry = create(:entry, list: channel, media: 'movie', imdb: 'tt0111161',
                             provider: drive, source_key: 'abc123')

      described_class.call(target)

      expect(entry.reload.provider).to eq(drive)
      expect(entry.source_key).to eq('abc123')
    end

    it 'reports how many overrides it cleared' do
      create(:entry, list: channel, name: 'One',   media: 'movie', imdb: 'tt1', provider: other_imdb)
      create(:entry, list: channel, name: 'Two',   media: 'movie', imdb: 'tt2', provider: dead_imdb)
      create(:entry, list: channel, name: 'Three', media: 'movie', imdb: 'tt3', provider: drive, source_key: 'k')

      expect(described_class.call(target).entries).to eq(2)
    end
  end

  # Pointing everything at MEGA would give every channel a template whose only variable is
  # a key none of the entries have.
  it 'refuses a direct provider as the target' do
    expect { described_class.call(drive) }.to raise_error(described_class::NotAnImdbSource)
  end
end
