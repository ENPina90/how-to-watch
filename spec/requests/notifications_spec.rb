# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Notifications' do
  # Eager, and declared before the source: creating a source fires the notifier, and it
  # can only warn admins that already exist.
  let!(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }

  let!(:expiring) do
    Source.create!(name: 'Player', slug: 'framerelay', kind: 'imdb', active: true, position: 1,
                   valid_until: 5.days.from_now.to_date,
                   templates: { 'movie' => 'https://framerelay.dev/embed/movie?imdb=%{imdb}' })
  end

  # Creating the source above fires the notifier, so the warnings already exist here.
  def warning_for(user) = Notification.where(user: user, kind: Notification::SOURCE_EXPIRING).first

  describe 'the page' do
    it 'shows an admin the provider warnings' do
      sign_in admin

      get notifications_path

      expect(response).to be_successful
      expect(response.body).to include('Player')
      expect(response.body).to include('about to expire')
    end

    it 'shows a member nothing, because provider warnings are not theirs' do
      sign_in member

      get notifications_path

      expect(response).to be_successful
      expect(response.body).not_to include('about to expire')
    end

    it 'asks a signed-out visitor to sign in' do
      get notifications_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'describes an expired provider differently from one merely due' do
      expiring.update!(valid_until: 3.days.ago.to_date)
      sign_in admin

      get notifications_path

      expect(response.body).to include('has expired')
    end
  end

  describe 'dismissing' do
    it 'takes one off the page' do
      sign_in admin
      notification = warning_for(admin)

      patch dismiss_notification_path(notification)

      expect(notification.reload).to be_dismissed
    end

    it 'clears them all at once' do
      sign_in admin

      patch dismiss_all_notifications_path

      expect(Notification.visible_to(admin).active).to be_empty
    end

    # The scope that finds it is the same one that decides whether it may be read.
    it 'will not let one person dismiss another persons notification' do
      second_admin = create(:user, :admin)
      # They joined after the source was created, so the nightly scan is what gives them
      # their copy of the warning.
      SourceExpiryNotifier.call
      notification = warning_for(second_admin)
      sign_in admin

      patch dismiss_notification_path(notification)

      expect(response).to have_http_status(:not_found)
      expect(notification.reload).not_to be_dismissed
    end

    # A member has a row only if they were an admin when it was written.
    it 'will not let a member dismiss an admin-only notification addressed to them' do
      notification = Notification.create!(user: member, kind: Notification::SOURCE_EXPIRING,
                                          dedupe_key: 'source_expiring:x:2026-01-01')
      sign_in member

      patch dismiss_notification_path(notification)

      expect(response).to have_http_status(:not_found)
      expect(notification.reload).not_to be_dismissed
    end
  end

  describe 'the badge in the navbar' do
    it 'appears for an admin with a warning waiting' do
      sign_in admin

      get root_path

      expect(response.body).to include('nav-dot')
    end

    it 'is absent once everything is dismissed' do
      sign_in admin
      patch dismiss_all_notifications_path

      get root_path

      expect(response.body).not_to include('nav-dot')
    end

    it 'is absent for a member, who has no provider warnings' do
      sign_in member

      get root_path

      expect(response.body).not_to include('nav-dot')
    end
  end
end
