require 'rails_helper'

# The adverts that fill the gap between programmes. Matched to the year of the film that has
# just finished, which is most of what makes a break feel like it belongs to the channel.
RSpec.describe CommercialReel do
  let!(:forties) { described_class.create!(label: '1940s', starts_year: 1940, ends_year: 1949, youtube_id: 'aaa') }
  let!(:eighty_seven) { described_class.create!(label: '1987', starts_year: 1987, ends_year: 1987, youtube_id: 'bbb') }
  let!(:twenty_ten) { described_class.create!(label: '2010-2019', starts_year: 2010, ends_year: 2019, youtube_id: 'ccc') }

  describe 'choosing a reel for a year' do
    it 'takes the reel for that exact year' do
      expect(described_class.for_year(1987)).to eq(eighty_seven)
    end

    it 'takes the era for a year that has no reel of its own' do
      expect(described_class.for_year(1944)).to eq(forties)
      expect(described_class.for_year(2015)).to eq(twenty_ten)
    end

    # A blank screen would be worse than adverts from the wrong decade, and a channel with a
    # tape library would reach for the nearest thing it had.
    it 'falls to the oldest reel for a film older than anything we hold' do
      expect(described_class.for_year(1928)).to eq(forties)
    end

    it 'falls to the newest for a film newer than anything we hold' do
      expect(described_class.for_year(2099)).to eq(twenty_ten)
    end

    it 'has nothing to offer when there are no reels at all' do
      described_class.delete_all

      expect(described_class.for_year(1987)).to be_nil
    end
  end

  describe 'where in a reel a break starts' do
    it 'never starts so late that the reel runs out mid-break' do
      eighty_seven.update!(duration_seconds: 600)

      200.times { expect(eighty_seven.random_offset_for(240)).to be_between(0, 360).inclusive }
    end

    # Every compilation is a quarter of an hour at the least, so the first few minutes are
    # safe to start in without knowing the runtime.
    it 'keeps to a safe window when the runtime is unknown' do
      expect(eighty_seven.duration_seconds).to be_nil

      200.times do
        expect(eighty_seven.random_offset_for(240))
          .to be_between(0, described_class::BLIND_WINDOW.to_i - 240).inclusive
      end
    end

    it 'starts at the beginning when the break is longer than the window' do
      expect(eighty_seven.random_offset_for(1.hour.to_i)).to eq(0)
    end
  end

  describe 'the embed' do
    let!(:youtube) do
      Source.create!(name: 'YouTube', slug: 'youtube', kind: 'direct', active: true, position: 9,
                     templates: { 'default' => 'https://www.youtube.com/embed/%{source_key}' })
    end

    it 'is built on the YouTube provider, starting where it is told' do
      url = eighty_seven.embed_url(start_at: 90)

      expect(url).to start_with('https://www.youtube.com/embed/bbb?')
      expect(url).to include('start=90').and include('autoplay=1')
    end

    # Nobody is meant to drive a commercial break.
    it 'asks for no player chrome' do
      expect(eighty_seven.embed_url).to include('controls=0').and include('disablekb=1')
    end

    it 'is nothing at all when the provider is gone' do
      youtube.update!(active: false)

      expect(eighty_seven.embed_url).to be_nil
    end
  end

  it 'refuses a span that runs backwards' do
    reel = described_class.new(label: 'x', youtube_id: 'zzz', starts_year: 1990, ends_year: 1989)

    expect(reel).not_to be_valid
  end
end
