require 'rails_helper'

# Dragging several ticked rows in the minimal view at once. They land together straight
# after the row they were dropped below, in the order they already had, and everything that
# followed moves down.
RSpec.describe 'Dragging several entries at once', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let!(:entries) do
    %w[A B C D E].each_with_index.to_h do |name, index|
      [name, create(:entry, list: list, name: name, position: index + 1)]
    end
  end

  before { sign_in user }

  def order
    list.entries.order(:position).pluck(:name)
  end

  def move(*names, after: nil, direction: 'asc')
    patch move_list_bulk_entries_path(list),
          params: { entry_ids: names.map { |name| entries[name].id },
                    after_id: after && entries[after].id,
                    direction: direction },
          as: :json
  end

  it 'drops the selection after the row it landed below' do
    move('B', 'D', after: 'E')

    expect(response).to have_http_status(:ok)
    expect(order).to eq(%w[A C E B D])
    expect(list.entries.order(:position).pluck(:position)).to eq([1, 2, 3, 4, 5])
  end

  it 'drops the selection at the top when nothing is above it' do
    move('D', 'E')

    expect(order).to eq(%w[D E A B C])
  end

  it 'keeps the order the selection already had, whatever order the ids came in' do
    move('D', 'B', after: 'A')

    expect(order).to eq(%w[A B D C E])
  end

  # On a reversed page the rows read E D C B A. Dropping B and D just below C there puts
  # them between C and A on screen, which is between A and C in the channel.
  it 'reads "after" the way the page showed it when the sort is reversed' do
    move('B', 'D', after: 'C', direction: 'desc')

    expect(order).to eq(%w[A B D C E])
  end

  it 'closes up gaps and ties while it is there' do
    entries['C'].update_column(:position, 9)
    entries['D'].update_column(:position, 9)

    # A B E C D, with C and D tied -- ties are broken by id, as normalize_entry_positions!
    # breaks them.
    move('A', after: 'E')

    expect(list.entries.order(:position).pluck(:position)).to eq([1, 2, 3, 4, 5])
    expect(order).to eq(%w[B E A C D])
  end

  it 'refuses an anchor that is not in the channel, and moves nothing' do
    stranger = create(:entry, list: create(:list), name: 'Elsewhere')

    patch move_list_bulk_entries_path(list),
          params: { entry_ids: [entries['B'].id], after_id: stranger.id }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(order).to eq(%w[A B C D E])
  end

  it 'answers a refusal with a status fetch can see, not a redirect' do
    sign_in create(:user)

    move('B', 'D', after: 'E')

    expect(response).to have_http_status(:forbidden)
    expect(order).to eq(%w[A B C D E])
  end

  it 'is not reachable over GET' do
    get "/lists/#{list.id}/bulk_entries/move"

    expect(response).to have_http_status(:not_found)
  end
end
