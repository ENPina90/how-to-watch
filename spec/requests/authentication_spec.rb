require 'rails_helper'

# The failure mode of a Devise upgrade is that everyone is locked out, and it is silent:
# the suite's `sign_in` helper bypasses the real flow. These go through the actual
# Warden strategy instead.
RSpec.describe 'Authentication', type: :request do
  let(:password) { 'sup3rsecret!' }
  let!(:user) { User.create!(email: 'flow@example.com', password: password) }

  it 'signs a user in with the right password' do
    post user_session_path, params: { user: { email: user.email, password: password } }

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response).to be_successful
  end

  it 'refuses the wrong password' do
    post user_session_path, params: { user: { email: user.email, password: 'nope' } }

    expect(response).not_to be_redirect
    expect(response.body).to include('name="user[password]"')
  end

  it 'signs out' do
    post user_session_path, params: { user: { email: user.email, password: password } }
    delete destroy_user_session_path

    get lists_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'still validates a digest hashed the way earlier Devise versions wrote them' do
    # Devise stores a plain BCrypt hash at the configured cost. If a future version ever
    # changes scheme or cost handling, every stored password stops working and the only
    # symptom is users being unable to log in. Building the digest with BCrypt directly
    # keeps this independent of whatever Devise does internally today.
    digest = BCrypt::Password.create('correct horse battery staple', cost: Devise.stretches)
    legacy = User.new(email: 'legacy@example.com')
    legacy.encrypted_password = digest

    expect(legacy.valid_password?('correct horse battery staple')).to be true
    expect(legacy.valid_password?('something else')).to be false
  end
end
