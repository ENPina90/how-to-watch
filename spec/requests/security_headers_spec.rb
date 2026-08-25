require 'rails_helper'

RSpec.describe 'Security headers', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  describe 'Permissions-Policy' do
    it 'reaches the object that actually builds responses' do
      # Rails copies config.action_dispatch.default_headers into
      # ActionDispatch::Response.default_headers from a railtie initializer that runs
      # before config/initializers/*. Setting only the config looks right and sends
      # nothing, which is how this regressed on the Rails 8.1 upgrade.
      expect(ActionDispatch::Response.default_headers).to include('Permissions-Policy')
    end

    subject(:policy) do
      get lists_path
      response.headers['Permissions-Policy'].to_s
    end

    it 'denies hardware and credential features the app never uses' do
      %w[camera microphone geolocation payment usb serial hid midi
         accelerometer gyroscope magnetometer display-capture].each do |feature|
        expect(policy).to include("#{feature}=()"), "expected #{feature} to be denied"
      end
    end

    it 'still allows what the embedded player needs' do
      # Denying these would break playback: the iframe cannot use a feature unless this
      # page delegates it.
      expect(policy).to include('autoplay=*')
      expect(policy).to include('fullscreen=*')
      expect(policy).to include('encrypted-media=*')
    end

    it 'does not emit Privacy Sandbox directives, which browsers log as unrecognised' do
      %w[browsing-topics run-ad-auction join-ad-interest-group attribution-reporting].each do |feature|
        expect(policy).not_to include(feature)
      end
    end
  end

  describe 'Content-Security-Policy' do
    before { get lists_path }

    it 'is report-only, so nothing is blocked yet' do
      expect(response.headers['Content-Security-Policy-Report-Only']).to be_present
      expect(response.headers['Content-Security-Policy']).to be_blank
    end

    it 'allows the CDNs the importmap pins' do
      csp = response.headers['Content-Security-Policy-Report-Only']

      expect(csp).to include('https://ga.jspm.io')
      expect(csp).to include('https://unpkg.com')
      expect(csp).to include('https://cdnjs.cloudflare.com')
    end

    it 'does not whitelist inline scripts, so violations stay visible' do
      csp = response.headers['Content-Security-Policy-Report-Only']
      script_src = csp[/script-src[^;]*/]

      expect(script_src).not_to include("'unsafe-inline'")
    end

    it 'locks down the directives that have no legitimate use here' do
      csp = response.headers['Content-Security-Policy-Report-Only']

      expect(csp).to include("object-src 'none'")
      expect(csp).to include("base-uri 'self'")
      expect(csp).to include("form-action 'self'")
    end
  end

  describe 'the player page' do
    it 'still renders with the policies applied' do
      entry = create(:entry, list: list, position: 1)

      get watch_entry_path(entry)

      expect(response).to be_successful
    end
  end
end
