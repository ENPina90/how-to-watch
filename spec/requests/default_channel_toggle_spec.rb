require 'rails_helper'

# The "Default Channel" badge is a control now: a star an admin clicks to set or unset it.
# Making a channel default subscribes every account to it, which is why the star is the
# admin's alone -- the same rule `default` has always been permitted under.
RSpec.describe 'The default channel star', :needs_provider, type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:member) { create(:user) }
  let(:list) { create(:list, user: admin, name: 'Noir') }

  describe 'who sees it' do
    it 'is there for an admin, unfilled when the channel is not default' do
      sign_in admin

      get list_path(list)

      expect(response.body).to include(%(id="default-#{list.id}"))
      expect(response.body).to include('class="fa-regular fa-star"')
      expect(response.body).to include(list_toggle_default_path(list))
    end

    it 'is filled when the channel is default' do
      sign_in admin
      list.update(default: true)

      get list_path(list)

      expect(response.body).to include('default-toggle--on')
      expect(response.body).to include('class="fa-solid fa-star"')
    end

    it 'is not there for anyone else' do
      sign_in member

      get list_path(list)

      expect(response.body).not_to include('default-toggle')
      expect(response.body).not_to include(list_toggle_default_path(list))
    end
  end

  describe 'clicking it' do
    it 'sets and unsets the channel as default' do
      sign_in admin

      expect { patch list_toggle_default_path(list) }.to change { list.reload.default? }.from(false).to(true)
      expect { patch list_toggle_default_path(list) }.to change { list.reload.default? }.from(true).to(false)
    end

    it 'streams the star back in its new state' do
      sign_in admin

      patch list_toggle_default_path(list), as: :turbo_stream

      expect(response.body).to include(%(target="default-#{list.id}"))
      expect(response.body).to include('fa-solid fa-star')
    end

    it 'refuses anyone who cannot set a default' do
      sign_in member

      expect { patch list_toggle_default_path(list) }.not_to change { list.reload.default? }
      expect(flash[:alert]).to eq('Only an admin can set the default channel.')
    end
  end
end
