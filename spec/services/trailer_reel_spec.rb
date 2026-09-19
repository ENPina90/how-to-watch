# frozen_string_literal: true

require 'rails_helper'

# Channel 0's running order, such as it is: a trailer at random, from channels the viewer
# may see, not one they have just watched.
RSpec.describe TrailerReel do
  let(:owner) { create(:user) }
  let(:list) { create(:list, user: owner, name: 'Films') }
  let!(:youtube) do
    Source.create!(name: 'YouTube', slug: 'youtube', kind: 'direct', active: true,
                   autoplay_param: 'autoplay',
                   templates: { 'default' => 'https://www.youtube.com/embed/%{source_key}' })
  end

  def with_trailer(name, youtube_id, in_list: list)
    create(:entry, list: in_list, name: name, trailer: "https://www.youtube.com/watch?v=#{youtube_id}")
  end

  def pick(user: owner, seen: [])
    described_class.new(user: user, seen: seen).pick
  end

  it 'plays a trailer with the film it belongs to' do
    entry = with_trailer('Blade Runner', 'aaaaaaaaaaa')

    trailer = pick

    expect(trailer.entry).to eq(entry)
    expect(trailer.youtube_id).to eq('aaaaaaaaaaa')
    expect(trailer.embed_url).to start_with('https://www.youtube.com/embed/aaaaaaaaaaa?')
  end

  # The page can only move on when the trailer ends if the player will say so.
  it 'asks the player to play at once and to report back' do
    with_trailer('Blade Runner', 'aaaaaaaaaaa')

    expect(pick.embed_url).to include('enablejsapi=1')
    # Once: YouTube obeys the first of two, and the provider writes `autoplay=0` unless asked.
    expect(pick.embed_url.scan(/autoplay=\d/)).to eq(['autoplay=1'])
  end

  it 'has nothing to play when no film has a trailer' do
    create(:entry, list: list, name: 'No trailer', trailer: nil)

    expect(pick).to be_nil
  end

  it 'has nothing to play without a YouTube provider to build the embed from' do
    with_trailer('Blade Runner', 'aaaaaaaaaaa')
    youtube.update!(active: false)

    expect(pick).to be_nil
  end

  it 'ignores a trailer that is not a YouTube link' do
    create(:entry, list: list, name: 'Elsewhere', trailer: 'https://vimeo.com/12345')

    expect(pick).to be_nil
  end

  describe 'which channels count' do
    let(:private_list) { create(:list, user: owner, name: 'Mine', private: true) }

    before { with_trailer('Hidden', 'hhhhhhhhhhh', in_list: private_list) }

    it "leaves out somebody else's private channel" do
      expect(pick(user: create(:user))).to be_nil
    end

    it 'leaves out every private channel for a visitor with no account' do
      expect(pick(user: nil)).to be_nil
    end

    it "includes the viewer's own private channel" do
      expect(pick(user: owner).youtube_id).to eq('hhhhhhhhhhh')
    end
  end

  describe 'what has been seen' do
    before do
      with_trailer('First', 'aaaaaaaaaaa')
      with_trailer('Second', 'bbbbbbbbbbb')
    end

    it 'skips a trailer seen lately' do
      expect(pick(seen: ['aaaaaaaaaaa']).youtube_id).to eq('bbbbbbbbbbb')
    end

    # Two trailers should alternate once both have been seen, rather than one sticking.
    it 'once everything has been seen, plays anything but the last one' do
      expect(pick(seen: %w[aaaaaaaaaaa bbbbbbbbbbb]).youtube_id).to eq('aaaaaaaaaaa')
    end

    it 'remembers a repeat once, at the end, and only so many' do
      seen = described_class.remember(%w[aaaaaaaaaaa bbbbbbbbbbb], 'aaaaaaaaaaa')
      expect(seen).to eq(%w[bbbbbbbbbbb aaaaaaaaaaa])

      long = (1..described_class::REMEMBERED).map { |n| format('v%010d', n) }
      expect(described_class.remember(long, 'new-video-x').size).to eq(described_class::REMEMBERED)
    end
  end

  # The same film filed in two channels carries the same trailer, and should not come up
  # twice as often for it.
  it 'counts a trailer filed twice as one, linked to the copy filed first' do
    first = with_trailer('Alien', 'ccccccccccc')
    with_trailer('Alien', 'ccccccccccc', in_list: create(:list, user: owner, name: 'Also'))

    trailers = Array.new(5) { pick }

    expect(trailers.map(&:entry).uniq).to eq([first])
  end
end
