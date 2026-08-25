require 'rails_helper'

# The CSP omits :unsafe_inline from script-src, so every inline <script> the app renders
# has to carry the response's nonce or it is a violation (logged today, blocked once this
# is enforced). Nothing in the request cycle catches a missing one -- it surfaces only in
# the browser console.
RSpec.describe 'Content Security Policy', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  def nonce_from_header
    response.headers['Content-Security-Policy-Report-Only'][/'nonce-([^']+)'/, 1]
  end

  def inline_scripts
    response.body.scan(/<script(?![^>]*\bsrc=)([^>]*)>/).flatten
  end

  describe 'every page that carries inline script' do
    it 'gives each one the response nonce' do
      get list_path(list)

      expect(response).to be_successful
      expect(inline_scripts).not_to be_empty

      nonce = nonce_from_header
      expect(nonce).to be_present

      inline_scripts.each do |attributes|
        expect(attributes).to include(%(nonce="#{nonce}")), "an inline <script> is missing the nonce"
      end
    end

    it 'covers the watch page, which has its own inline block' do
      entry = create(:entry, list: list, position: 1, media: 'movie', imdb: 'tt1')

      get watch_entry_path(entry)

      expect(response).to be_successful
      nonce = nonce_from_header
      inline_scripts.each { |attributes| expect(attributes).to include(%(nonce="#{nonce}")) }
    end
  end

  describe 'the nonce itself' do
    it 'differs between responses' do
      # A session-derived nonce repeats for every response in a session, and is blank
      # before a session exists.
      get list_path(list)
      first = nonce_from_header

      get list_path(list)

      expect(nonce_from_header).to be_present
      expect(nonce_from_header).not_to eq(first)
    end
  end

  describe 'the policy' do
    it 'does not permit inline script' do
      get list_path(list)

      script_src = response.headers['Content-Security-Policy-Report-Only'][/script-src[^;]*/]

      expect(script_src).to include("'nonce-")
      expect(script_src).not_to include("'unsafe-inline'")
    end

    it 'still permits inline style, which is deliberate' do
      # 101 inline style attributes across the views. This is the remaining reason the
      # policy is report-only rather than enforced.
      get list_path(list)

      style_src = response.headers['Content-Security-Policy-Report-Only'][/style-src[^;]*/]

      expect(style_src).to include("'unsafe-inline'")
    end
  end
end
