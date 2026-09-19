# frozen_string_literal: true

require 'rails_helper'

# The remediation path: the card says which entry and which channel, and "View" takes you to
# the entry's own page, where the runtime is a field on the form.
RSpec.describe 'Missing runtime notices' do
  let!(:admin) { create(:user, :admin) }
  let(:channel) { create(:list, name: 'Annals', default: true) }
  let(:entry) { create(:entry, list: channel, name: 'The Worm', media: 'episode', length: nil) }

  let!(:notice) do
    Notification.create!(user: admin, kind: Notification::MISSING_RUNTIME, subject: entry,
                         dedupe_key: "missing_runtime:#{entry.id}",
                         data: { 'name' => entry.name, 'list' => channel.name,
                                 'channel' => channel.name, 'media' => 'episode', 'guess' => 30 })
  end

  it 'names the entry and the channel it is missing from' do
    sign_in admin

    get notifications_path

    expect(response.body).to include('The Worm', 'cable leaves it out of Annals')
  end

  # Rows written while cable still guessed carry the figure. Nothing assumes it now, and a
  # card that named it would describe a schedule that no longer exists.
  it 'does not repeat a guess an old row still carries' do
    sign_in admin

    get notifications_path

    expect(response.body).not_to include('30 minutes')
  end

  # Most of what the sweep finds is on no channel yet, so the card has to say what will
  # happen rather than describe a schedule that does not exist.
  it 'says what will happen to an entry nothing schedules' do
    shelved = create(:entry, list: create(:list, name: 'Shelf'), name: 'Unscheduled', length: nil)
    Notification.create!(user: admin, kind: Notification::MISSING_RUNTIME, subject: shelved,
                         dedupe_key: "missing_runtime:#{shelved.id}",
                         data: { 'name' => 'Unscheduled', 'list' => 'Shelf', 'channel' => nil,
                                 'media' => 'movie', 'guess' => 100 })

    sign_in admin

    get notifications_path

    expect(response.body).to include('Unscheduled')
    expect(response.body).to include('off any channel it joins')
  end

  it 'sends you to the entry, and gets out of the way when you go' do
    sign_in admin

    get notifications_path

    expect(response.body).to include(dismiss_notification_path(notice, view: true))
  end

  # It is a job to do, not a fault to put right in a hurry -- the entry is held off the dial,
  # not playing wrongly on it.
  it 'reads as information rather than a warning' do
    expect(helper_tone).to eq(:info)
  end

  # Everything the scans raise is an admin's business, and stays hidden from everyone else
  # even if the row somehow exists.
  it 'is never shown to a member who is not an admin' do
    member = create(:user)
    Notification.create!(user: member, kind: Notification::MISSING_RUNTIME, subject: entry,
                         dedupe_key: "missing_runtime:#{entry.id}", data: { 'name' => entry.name })

    sign_in member
    get notifications_path

    expect(response.body).not_to include('has no runtime')
  end

  def helper_tone
    Class.new { include NotificationsHelper }.new.notification_tone(notice)
  end
end
