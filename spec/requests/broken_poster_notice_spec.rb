# frozen_string_literal: true

require 'rails_helper'

# The remediation path: the notification says which entry, "View" takes you to it and gets
# out of the way, and the entry's own page carries the poster picker so the fix is one
# more click rather than a trip back to the channel it lives in.
RSpec.describe 'Broken poster notices' do
  let!(:admin) { create(:user, :admin) }
  let(:list) { create(:list, name: 'Funny') }
  let(:entry) { create(:entry, list: list, name: 'Fantasmas', pic: 'https://img.test/gone.jpg') }

  let!(:notice) do
    Notification.create!(user: admin, kind: Notification::BROKEN_POSTER, subject: entry,
                         dedupe_key: "broken_poster:#{entry.id}:abc123",
                         data: { 'name' => entry.name, 'list' => list.name, 'source' => 'poster',
                                 'reason' => 'HTTP 404', 'url' => 'https://img.test/gone.jpg' })
  end

  describe 'the notification' do
    it 'names the entry and the channel it is in' do
      sign_in admin

      get notifications_path

      expect(response.body).to include('Fantasmas', 'Funny')
    end

    it 'offers View as a PATCH, because following it is also a write' do
      sign_in admin

      get notifications_path

      expect(response.body).to include(dismiss_notification_path(notice, view: true))
    end

    it 'sends you to the entry and clears itself in one click' do
      sign_in admin

      patch dismiss_notification_path(notice, view: true)

      expect(response).to redirect_to(entry_path(entry))
      expect(notice.reload).to be_dismissed
    end

    it 'stays off the page afterwards' do
      sign_in admin
      patch dismiss_notification_path(notice, view: true)

      get notifications_path

      expect(response.body).not_to include('Fantasmas')
    end

    # The expiry warnings are the other sort: a state to keep an eye on, which should not
    # disappear just because somebody looked at the sources page.
    it 'leaves an expiry warning as a plain link that does not dismiss' do
      warning = Notification.create!(user: admin, kind: Notification::SOURCE_EXPIRING,
                                     dedupe_key: 'source_expiring:1:2030-01-01',
                                     data: { 'name' => 'Player', 'slug' => 'player',
                                             'valid_until' => '2030-01-01' })
      sign_in admin

      get notifications_path

      expect(response.body).not_to include(dismiss_notification_path(warning, view: true))
    end
  end

  describe 'the entry page' do
    it 'carries the poster picker for somebody who can edit it' do
      sign_in admin

      get entry_path(entry)

      expect(response.body).to include('Change poster')
      expect(response.body).to include('posterModal')
    end

    it 'does not offer it to somebody who cannot edit the entry' do
      sign_in create(:user)

      get entry_path(entry)

      expect(response.body).not_to include('Change poster')
    end
  end
end
