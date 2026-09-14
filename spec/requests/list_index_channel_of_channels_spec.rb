require 'rails_helper'

# A channel that only holds other channels, on the home page. Its card counted the channel's
# own rows and showed a test card, so every channel of channels read "0 entries" beside a
# "please stand by" however much was inside it.
RSpec.describe 'A channel of channels on the home page', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:hub) { create(:list, user: user, name: 'Holiday', ordered: true) }
  let(:child) { create(:list, user: user, name: 'Christmas') }
  let(:grandchild) { create(:list, user: user, name: 'Hanukkah') }
  let!(:elf) { create(:entry, list: child, name: 'Elf', imdb: 'tt1', position: 1) }
  let!(:klaus) { create(:entry, list: child, name: 'Klaus', imdb: 'tt2', position: 2) }
  let!(:nights) { create(:entry, list: grandchild, name: 'Eight Crazy Nights', imdb: 'tt3', position: 1) }

  before do
    sign_in user
    child.add_to_parent(hub)
    grandchild.add_to_parent(child)
  end

  def card_meta_for(name)
    response.body[%r{<p class="list-card-name">#{name}</p>\s*<p class="list-card-meta">(.*?)</p>}m, 1]
      &.gsub(/<[^>]+>/, '')&.squish
  end

  describe 'the count' do
    it 'counts everything under the channel, however deep' do
      get lists_path

      expect(card_meta_for('Holiday')).to eq('3')
    end

    it 'agrees with the number on the channel’s own page' do
      expect(List.with_entries_count.find(hub.id).entries_count).to eq(hub.total_entry_count)
    end

    it 'counts a channel held in two places once' do
      grandchild.add_to_parent(hub)

      expect(List.with_entries_count.find(hub.id).entries_count).to eq(3)
    end

    it 'counts on the phone too' do
      get lists_path, headers: { 'HTTP_USER_AGENT' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)' }

      expect(response.body).to match(%r{Holiday.*?<span class="m-channel__count">3</span>}m)
    end
  end

  # The card plays what the channel's own play button would: the next unwatched entry
  # across the channels inside it, watched from this channel rather than the one it lives in.
  describe 'the card' do
    it 'plays the next thing under the channel, from the channel' do
      get lists_path

      expect(response.body).to include(watch_entry_path(elf, channel: hub.id))
    end

    it 'skips what this member has already watched' do
      elf.mark_completed_by!(user)

      get lists_path

      expect(response.body).to include(watch_entry_path(klaus, channel: hub.id))
      expect(response.body).not_to include(watch_entry_path(elf, channel: hub.id))
    end

    it 'keeps a poster once everything under it is watched' do
      [elf, klaus, nights].each { |entry| entry.mark_completed_by!(user) }

      get lists_path

      expect(response.body).to include(watch_entry_path(elf, channel: hub.id))
    end

    it 'still stands by for a channel with nothing anywhere under it' do
      create(:list, user: user, name: 'Nothing Yet')

      get lists_path

      expect(response.body).to match(%r{please_stand_by\.png" alt="Nothing Yet"})
    end
  end
end
