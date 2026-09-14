# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NewEpisodeScanJob do
  it 'runs the sweep' do
    result = NewEpisodeNotifier::Result.new(checked: 3, added: 1, held_back: 0, notified: 2, failed: 0)
    allow(NewEpisodeNotifier).to receive(:call).and_return(result)

    described_class.perform_now

    expect(NewEpisodeNotifier).to have_received(:call)
  end

  it 'is on the weekly schedule' do
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))

    expect(schedule.values.map { |job| job['class'] }).to include('NewEpisodeScanJob')
  end
end
