require 'rails_helper'

# A channel that only holds other channels, on the home page. Its card counted the channel's
# own rows and showed a test card, so every channel of channels read "0 entries" beside a
# "please stand by" however much was inside it.
RSpec.describe 'A channel of channels on the home page', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:hub) { create(:list, user: user, name: 'Holiday') }
  let(:child) { create(:list, user: user, name: 'Christmas') }
  let(:grandchild) { create(:list, user: user, name: 'Hanukkah') }

  before do
    sign_in user
    create(:entry, list: child, name: 'Elf', imdb: 'tt1', position: 1)
    create(:entry, list: child, name: 'Klaus', imdb: 'tt2', position: 2)
    create(:entry, list: grandchild, name: 'Eight Crazy Nights', imdb: 'tt3', position: 1)
    child.add_to_parent(hub)
    grandchild.add_to_parent(child)
  end

  def card_meta_for(name)
    response.body[%r{<p class="list-card-name">#{name}</p>\s*<p class="list-card-meta">\s*([^<]*?)\s*</p>}m, 1]
  end

  describe 'the count' do
    it 'counts everything under the channel, however deep' do
      get lists_path

      expect(card_meta_for('Holiday')).to eq('3 entries')
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
end
