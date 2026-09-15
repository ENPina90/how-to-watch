require 'rails_helper'

# The Position field on the entry edit form. It used to write the typed number straight onto
# the entry and then try to shift the others -- after the save, when the entry already
# stood at its new number, so nothing moved and two entries shared the place. A request
# that did not send a position at all read as position 0 and pushed every entry above this
# one down a place.
RSpec.describe 'Changing an entry’s position from the edit form', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let!(:entries) do
    %w[A B C D E].each_with_index.map do |name, index|
      create(:entry, list: list, name: name, position: index + 1)
    end
  end

  before { sign_in user }

  def order
    list.entries.order(:position).pluck(:name)
  end

  def positions
    list.entries.order(:position).pluck(:position)
  end

  it 'moves an entry up and pushes the ones in between down' do
    patch entry_path(entries[3]), params: { entry: { position: '2' } }

    expect(order).to eq(%w[A D B C E])
    expect(positions).to eq([1, 2, 3, 4, 5])
  end

  it 'moves an entry down and pulls the ones in between up' do
    patch entry_path(entries[0]), params: { entry: { position: '4' } }

    expect(order).to eq(%w[B C D A E])
    expect(positions).to eq([1, 2, 3, 4, 5])
  end

  it 'stops at either end of the channel' do
    patch entry_path(entries[2]), params: { entry: { position: '99' } }
    expect(order).to eq(%w[A B D E C])

    patch entry_path(entries[2]), params: { entry: { position: '0' } }
    expect(order).to eq(%w[C A B D E])
  end

  it 'leaves the order alone when the request says nothing about position' do
    patch entry_path(entries[3]), params: { entry: { note: 'Only a note' } }

    expect(order).to eq(%w[A B C D E])
    expect(positions).to eq([1, 2, 3, 4, 5])
    expect(entries[3].reload.note).to eq('Only a note')
  end

  it 'leaves the order alone when the position is blank or unchanged' do
    patch entry_path(entries[3]), params: { entry: { position: '' } }
    patch entry_path(entries[3]), params: { entry: { position: '4', note: 'Same place' } }

    expect(order).to eq(%w[A B C D E])
    expect(entries[3].reload.note).to eq('Same place')
  end

  # A channel with gaps and ties -- a bulk import, or a delete -- is still an order. The
  # number typed in is a place in that order, the way dragging treats it.
  it 'reads the typed number as a place in the order when the positions have gaps' do
    list.entries.find_by(name: 'C').update_column(:position, 7)
    list.entries.find_by(name: 'D').update_column(:position, 9)
    list.entries.find_by(name: 'E').update_column(:position, 12)

    patch entry_path(list.entries.find_by(name: 'E')), params: { entry: { position: '2' } }

    expect(order).to eq(%w[A E B C D])
    expect(positions).to eq([1, 2, 3, 4, 5])
  end

  it 'redraws the page after a reorder, since every card in between has a new number' do
    patch entry_path(entries[3]), params: { entry: { position: '1' } }, as: :turbo_stream,
                                  headers: { 'HTTP_REFERER' => list_path(list, view: 'minimal') }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(list_path(list, view: 'minimal'))
  end

  it 'still replaces just the card when the order did not change' do
    patch entry_path(entries[3]), params: { entry: { position: '4', note: 'Same place' } }, as: :turbo_stream

    expect(response.media_type).to eq('text/vnd.turbo-stream.html')
  end

  it 'saves the other fields along with the move' do
    patch entry_path(entries[4]), params: { entry: { position: '1', category: 'Moved' } }

    expect(order.first).to eq('E')
    expect(entries[4].reload.category).to eq('Moved')
  end
end
