require 'rails_helper'
require 'rake'

# The same rule as the callback, applied to what is already in the database.
RSpec.describe 'entries:backfill_categories', :needs_provider do
  let(:list) { create(:list) }

  before(:all) do
    Rake::Task.define_task(:environment)
    Rake.application.rake_require('tasks/entry_categories') unless Rake::Task.task_defined?('entries:backfill_categories')
  end

  before { Rake::Task['entries:backfill_categories'].reenable }

  def run
    # The task reports what it did; the report is not what is under test.
    expect { Rake::Task['entries:backfill_categories'].invoke }.to output.to_stdout
  end

  it 'fills a series with its own name' do
    entry = create(:entry, list: list, media: 'series', name: 'Star Trek')
    entry.update_columns(category: nil, series: nil)

    run

    expect(entry.reload.category).to eq('Star Trek')
  end

  it 'fills an episode with the series it belongs to' do
    entry = create(:entry, list: list, media: 'episode', name: 'Star Trek - The Cage',
                           series: 'Star Trek', season: 1, episode: 1)
    entry.update_columns(category: '')

    run

    expect(entry.reload.category).to eq('Star Trek')
  end

  it 'leaves a category that is already set' do
    entry = create(:entry, list: list, media: 'series', name: 'Star Trek', category: 'Comfort')

    run

    expect(entry.reload.category).to eq('Comfort')
  end

  it 'leaves a movie alone' do
    entry = create(:entry, list: list, media: 'movie', name: 'Alien')
    entry.update_columns(category: nil)

    run

    expect(entry.reload.category).to be_nil
  end

  # An episode with no series recorded has no show name to file it under; the task says so
  # rather than inventing one from the episode's own title.
  it 'passes over an entry with no show name' do
    entry = create(:entry, list: list, media: 'episode', name: 'Orphan', season: 1, episode: 1)
    entry.update_columns(category: nil, series: nil)

    run

    expect(entry.reload.category).to be_nil
  end
end
