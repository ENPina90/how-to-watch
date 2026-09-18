# frozen_string_literal: true

require 'rails_helper'

# What deleting an episode does to its show's current-episode pointer, `entries.current_id`
# -- the pre-multi-user column that is still what a signed-out visitor and a member with no
# saved position are shown.
RSpec.describe Subentry, 'being destroyed' do
  let(:list) { create(:list) }
  let(:show) { create(:entry, list: list, media: 'series', name: 'Centipede') }

  let!(:first) { described_class.create!(entry: show, season: 1, episode: 1, name: 'Pilot') }
  let!(:second) { described_class.create!(entry: show, season: 1, episode: 2, name: 'Second') }
  let!(:third) { described_class.create!(entry: show, season: 1, episode: 3, name: 'Third') }

  # The bug. It used to move the pointer on every delete, whichever episode went -- so
  # clearing out a stray episode at the end of a show sent everybody without a saved
  # position to the one before it.
  it 'leaves the pointer alone when it was on some other episode' do
    show.update!(current_id: first.id)

    third.destroy

    expect(show.reload.current_id).to eq(first.id)
  end

  it 'moves the pointer back one when it was on the episode deleted' do
    show.update!(current_id: third.id)

    third.destroy

    expect(show.reload.current_id).to eq(second.id)
  end

  it 'clears the pointer when the episode deleted was the first and the pointer was on it' do
    show.update!(current_id: first.id)

    first.destroy

    expect(show.reload.current_id).to be_nil
  end

  it 'leaves a show with no pointer without one' do
    second.destroy

    expect(show.reload.current_id).to be_nil
  end
end
