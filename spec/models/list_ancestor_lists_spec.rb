require 'rails_helper'

# The channels a list sits inside, which is how the Now Playing card knows which part of the
# dial a channel's page belongs to. The mirror of descendant_lists, and bound the same way.
RSpec.describe List, '#ancestor_lists' do
  let(:user) { create(:user) }

  def nest(child, inside:)
    ListRelationship.create!(parent_list: inside, child_list: child, position: 1)
  end

  it 'is empty for a list inside nothing' do
    expect(create(:list, user: user).ancestor_lists).to eq([])
  end

  it 'reaches parents and theirs' do
    list, parent, grandparent = create_list(:list, 3, user: user)
    nest(list, inside: parent)
    nest(parent, inside: grandparent)

    expect(list.ancestor_lists).to contain_exactly(parent, grandparent)
  end

  # A channel further up than MAX_NESTING does not gather this list's entries, so it is not
  # a channel this list is part of.
  it 'stops as deep as a channel gathers from' do
    chain = create_list(:list, List::MAX_NESTING + 2, user: user)
    chain.each_cons(2) { |child, parent| nest(child, inside: parent) }

    expect(chain.first.ancestor_lists).to eq(chain[1..List::MAX_NESTING])
  end

  # Cycles are refused when a channel is added, but a read should not rely on that having
  # always held.
  it 'survives a cycle already in the database' do
    a, b = create_list(:list, 2, user: user)
    nest(a, inside: b)
    ListRelationship.new(parent_list: a, child_list: b, position: 1).save!(validate: false)

    expect(a.ancestor_lists).to eq([b])
  end
end
