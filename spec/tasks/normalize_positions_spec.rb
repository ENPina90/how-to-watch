require 'rails_helper'
require 'rake'

# Bulk imports leave positions sharing numbers and skipping others -- a season import can
# file every episode at the position its parent had. `current` is one of those numbers
# rather than an entry id, so renumbering has to carry it along.
RSpec.describe 'entries:normalize_positions', :needs_provider do
  let(:list) { create(:list) }

  before(:all) do
    Rake::Task.define_task(:environment)
    Rake.application.rake_require('tasks/entry_positions') unless Rake::Task.task_defined?('entries:normalize_positions')
  end

  before { Rake::Task['entries:normalize_positions'].reenable }

  def run
    expect { Rake::Task['entries:normalize_positions'].invoke }.to output.to_stdout
  end

  def positioned(*positions)
    positions.each_with_index.map do |position, i|
      create(:entry, list: list, name: "Entry #{i}", imdb: "tt000#{i}").tap { |e| e.update_column(:position, position) }
    end
  end

  it 'renumbers shared and skipped positions into a run' do
    positioned(1, 1, 1, 7)

    run

    expect(list.entries.order(:position).pluck(:position)).to eq([1, 2, 3, 4])
  end

  it 'keeps current pointing at the entry it pointed at' do
    entries = positioned(1, 1, 1, 7)
    list.update_column(:current, 7)

    run

    expect(list.reload.current).to eq(entries.last.reload.position)
    expect(list.find_entry_by_position(:current)).to eq(entries.last)
  end

  it 'leaves a channel whose positions already run 1..N alone' do
    positioned(1, 2, 3)
    list.update_column(:current, 2)

    expect { run }.not_to change { list.entries.order(:id).pluck(:position) }
    expect(list.reload.current).to eq(2)
  end

  it 'orders ties the same way twice' do
    positioned(1, 1, 1, 1)
    first = list.entries.order(:position, :id).pluck(:id)

    run

    expect(list.entries.order(:position).pluck(:id)).to eq(first)
  end
end
