# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Managing source providers' do
  let!(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }

  let!(:source) do
    Source.create!(name: 'Player', slug: 'framerelay', kind: 'imdb', active: true, position: 1,
                   valid_until: 10.days.from_now.to_date,
                   templates: { 'movie' => 'https://framerelay.dev/embed/movie?imdb=%{imdb}' })
  end

  describe 'the index' do
    it 'shows an admin every provider and what state it is in' do
      sign_in admin

      get sources_path

      expect(response).to be_successful
      expect(response.body).to include('framerelay')
      expect(response.body).to include('source-card--soon')
    end

    it 'marks an expired provider differently from one merely close' do
      source.update!(valid_until: 2.days.ago.to_date)
      sign_in admin

      get sources_path

      expect(response.body).to include('source-card--expired')
    end

    it 'turns away a member' do
      sign_in member

      get sources_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'renewing' do
    it 'buys another year from the date it already had' do
      sign_in admin

      patch renew_source_path(source)

      expect(source.reload.valid_until).to eq(10.days.from_now.to_date + 1.year)
    end

    # Renewing is how an admin answers the warning, so the warning has to go with it.
    it 'clears the warning it was answering' do
      sign_in admin
      expect(Notification.where(user: admin, kind: Notification::SOURCE_EXPIRING)).to be_present

      patch renew_source_path(source)

      expect(Notification.where(user: admin, kind: Notification::SOURCE_EXPIRING)).to be_empty
    end

    it 'turns away a member' do
      sign_in member

      patch renew_source_path(source)

      expect(source.reload.valid_until).to eq(10.days.from_now.to_date)
    end
  end

  describe 'deactivating' do
    it 'switches it off without deleting it' do
      sign_in admin

      patch deactivate_source_path(source)

      expect(source.reload).not_to be_active
      expect(Source.find_by(id: source.id)).to be_present
    end

    # Nothing plays through it any more, so there is nothing left to warn about.
    it 'also clears its warning' do
      sign_in admin

      patch deactivate_source_path(source)

      expect(Notification.where(user: admin, kind: Notification::SOURCE_EXPIRING)).to be_empty
    end

    it 'turns away a member' do
      sign_in member

      patch deactivate_source_path(source)

      expect(source.reload).to be_active
    end
  end

  describe 'the test page' do
    it 'embeds a known film for an imdb provider' do
      sign_in admin

      get test_source_path(source)

      expect(response).to be_successful
      expect(response.body).to include(Source::PROBE_IMDB)
    end

    # A direct provider addresses one file by a key, so there is nothing to probe it with
    # until something is filed under it. Saying so beats an empty frame.
    it 'explains itself for a direct provider with nothing filed under it' do
      direct = Source.create!(name: 'MEGA', slug: 'mega', kind: 'direct', active: true, position: 9,
                              templates: { 'default' => 'https://mega.nz/embed/%{source_key}' })
      sign_in admin

      get test_source_path(direct)

      expect(response).to be_successful
      expect(response.body).to include('plays files by key')
    end

    it 'turns away a member' do
      sign_in member

      get test_source_path(source)

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'ordering' do
    let!(:second) do
      Source.create!(name: 'VidSrc 2', slug: 'vidsrc2', kind: 'imdb', active: true, position: 2,
                     templates: { 'movie' => 'https://vidsrc2.ru/embed/movie?imdb=%{imdb}' })
    end

    it 'writes the dragged order back as positions' do
      sign_in admin

      patch reorder_sources_path, params: { ids: [second.id, source.id] }

      expect(response).to have_http_status(:no_content)
      expect(second.reload.position).to eq(1)
      expect(source.reload.position).to eq(2)
    end

    # Position is not decoration: the first active imdb provider is what a channel falls
    # back to when its own is gone, so dragging one to the top changes what plays.
    it 'changes which provider a channel falls back to' do
      list = create(:list, user: admin, provider: nil)
      entry = create(:entry, list: list, media: 'movie', imdb: 'tt0111161', provider: nil)
      sign_in admin

      patch reorder_sources_path, params: { ids: [second.id, source.id] }

      expect(entry.reload.resolved_source).to eq(second)
    end

    # These have collided before, because the seed and the UI both wrote them. Any drag
    # renumbers the whole list, which repairs that.
    it 'renumbers into a clean run even when positions had collided' do
      Source.update_all(position: 1)
      sign_in admin

      patch reorder_sources_path, params: { ids: [source.id, second.id] }

      expect(Source.order(:position).pluck(:position).first(2)).to eq([1, 2])
    end

    it 'turns away a member' do
      sign_in member

      patch reorder_sources_path, params: { ids: [second.id, source.id] }

      expect(second.reload.position).to eq(2)
    end
  end

  # The navbar link and the page have to agree about who may be here.
  describe 'while viewing the site as someone else' do
    it 'refuses, the way /admin does' do
      sign_in admin
      post impersonate_user_path(member)

      get sources_path

      expect(response).to redirect_to(root_path)
    end
  end
end
