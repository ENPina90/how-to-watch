# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Checking a Letterboxd handle', type: :request do
  let(:body) { Rails.root.join('spec/fixtures/letterboxd/diary.xml').read }

  def json = JSON.parse(response.body)

  # The sign-up form asks before the account exists, so this cannot sit behind Devise
  # whatever the site's access mode is.
  it 'answers a signed-out visitor' do
    stub_request(:get, 'https://letterboxd.com/testmember/rss/').to_return(status: 200, body: body)

    get letterboxd_check_path(username: 'testmember')

    expect(response).to have_http_status(:ok)
    expect(json['status']).to eq('ok')
  end

  it 'reports a handle with no public diary, and says why that happens' do
    stub_request(:get, 'https://letterboxd.com/ghost/rss/').to_return(status: 404, body: '')

    get letterboxd_check_path(username: 'ghost')

    expect(json['status']).to eq('not_found')
    expect(json['hint']).to match(/not your display name/i)
  end

  it 'rejects a malformed handle without going out to Letterboxd' do
    get letterboxd_check_path(username: '../../secrets')

    expect(json['status']).to eq('invalid')
    expect(a_request(:get, %r{letterboxd\.com})).not_to have_been_made
  end

  it 'treats a Letterboxd outage as unknown rather than as a bad handle' do
    stub_request(:get, 'https://letterboxd.com/testmember/rss/').to_timeout

    get letterboxd_check_path(username: 'testmember')

    expect(json['status']).to eq('not_found')
  end
end

RSpec.describe 'Opting in at sign-up', type: :request do
  let(:body) { Rails.root.join('spec/fixtures/letterboxd/diary.xml').read }

  before do
    stub_request(:get, %r{letterboxd\.com/.+/rss/}).to_return(status: 200, body: body)
    stub_request(:get, %r{api\.themoviedb\.org}).to_return(status: 200, body: { imdb_id: 'tt1' }.to_json)
  end

  it 'offers the opt-in beside the username field' do
    get new_user_registration_path

    expect(response.body).to include('letterboxd-check')
    expect(response.body).to include('user[letterboxd_enabled]')
  end

  # Devise drops anything it was not told to permit, which is what had been happening to
  # the username since the field was added.
  it 'keeps the username and the opt-in through sign-up' do
    post user_registration_path, params: {
      user: {
        email: 'new@example.com', password: 'password', password_confirmation: 'password',
        username: 'testmember', letterboxd_enabled: '1'
      }
    }

    user = User.find_by(email: 'new@example.com')
    expect(user.username).to eq('testmember')
    expect(user).to be_letterboxd_enabled
  end

  it 'refuses the opt-in when no username was given' do
    post user_registration_path, params: {
      user: {
        email: 'new@example.com', password: 'password', password_confirmation: 'password',
        username: '', letterboxd_enabled: '1'
      }
    }

    expect(User.find_by(email: 'new@example.com')).to be_nil
    expect(response.body).to include('needed to link a Letterboxd account')
  end
end
