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

  it 'names the entry, the channel and the length being assumed' do
    sign_in admin

    get notifications_path

    expect(response.body).to include('The Worm', 'Annals', '30 minutes')
  end

  it 'sends you to the entry, and gets out of the way when you go' do
    sign_in admin

    get notifications_path

    expect(response.body).to include(dismiss_notification_path(notice, view: true))
  end

  # It is a job to do, not a fault to put right in a hurry -- nothing is broken until the
  # guess turns out to be longer than the file.
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
