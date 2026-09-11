require 'rails_helper'
require 'rake'

# The guide reaches three days behind the present; this is what puts something there to
# find on a dial that has only ever laid out one day at a time.
RSpec.describe 'cable:backfill' do
  let(:user) { create(:user) }

  let!(:provider) do
    Source.create!(
      name: 'Primary', kind: 'imdb', active: true, position: 1,
      templates: { 'movie' => 'https://p.test/movie?imdb=%{imdb}' }
    )
  end

  let!(:channel) { create(:list, user: user, provider: provider, default: true, name: 'Channel One') }
  let!(:entry) do
    create(:entry, list: channel, name: 'The Death of Harvey', media: 'movie',
                   length: 90, position: 1, imdb: 'tt0000001')
  end

  before(:all) do
    Rake::Task.define_task(:environment)
    Rake.application.rake_require('tasks/cable') unless Rake::Task.task_defined?('cable:backfill')
  end

  before { Rake::Task['cable:backfill'].reenable }

  def run(*args)
    # The task reports what it did; the report is not what is under test.
    expect { Rake::Task['cable:backfill'].invoke(*args) }.to output.to_stdout
  end

  it 'lays out the days behind today and leaves today alone' do
    run('3')

    days = CableSlot.where(list: channel).distinct.pluck(:airs_on).sort

    expect(days).to eq([3, 2, 1].map { |back| CableSchedule.today - back })
  end

  it 'defaults to as many days as the guide reaches back' do
    run

    expect(CableSlot.where(list: channel).distinct.count(:airs_on))
      .to eq(CableSchedule::GUIDE_LEAD_HOURS / 24)
  end

  # A day that really did air is a record of what the channel played. Laying it out again
  # would replace it with a plausible-looking day nobody watched.
  it 'leaves a day that already has a schedule exactly as it was' do
    yesterday = CableSchedule.today - 1
    CableSchedule.build_day!(channel, yesterday)
    before_ids = CableSlot.where(list: channel, airs_on: yesterday).order(:position).pluck(:entry_id, :starts_at)

    run('1')

    after_ids = CableSlot.where(list: channel, airs_on: yesterday).order(:position).pluck(:entry_id, :starts_at)
    expect(after_ids).to eq(before_ids)
  end

  # Within what the pruning keeps, or the next run of the job deletes the lot again.
  it 'does not write a day the pruning will immediately remove' do
    run

    oldest = CableSlot.where(list: channel).minimum(:airs_on)

    expect(oldest).to be >= CableSchedule.today - CableSchedule::RETAIN_DAYS
  end
end
