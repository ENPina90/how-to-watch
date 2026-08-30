require 'rails_helper'

# Signing in came round every couple of weeks at best, and on every browser restart at
# worst. These are the three things that decided that.
RSpec.describe 'Staying signed in', type: :request do
  let(:user) { create(:user, password: 'password123', password_confirmation: 'password123') }

  def sign_in_through_the_form(remember: '1')
    post user_session_path, params: {
      user: { email: user.email, password: 'password123', remember_me: remember }
    }
  end

  it 'sets a remember cookie that outlives the browser session' do
    sign_in_through_the_form

    expect(response.cookies['remember_user_token']).to be_present
    expect(user.reload.remember_created_at).to be_present
  end

  it 'remembers for a year rather than a fortnight' do
    expect(Devise.remember_for).to eq(1.year)
  end

  # The year runs from the last visit, not from the last time a password was typed.
  it 'extends the period on a visit that arrives on the cookie' do
    expect(Devise.extend_remember_period).to be(true)
  end

  it 'offers the box already ticked' do
    get new_user_session_path

    checkbox = response.body[/<input[^>]*user_remember_me[^>]*>/]
    expect(checkbox).to include('checked')
  end

  it 'still honours the box being cleared' do
    sign_in_through_the_form(remember: '0')

    expect(response.cookies['remember_user_token']).to be_nil
  end
end
