# frozen_string_literal: true

require 'rails_helper'

# /trailers: a trailer for something in the catalogue, then another, each with a way to the
# film. Which trailer is TrailerReel's business; this is the page around it.
RSpec.describe 'Trailers', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, name: 'Films') }
  let!(:youtube) do
    Source.create!(name: 'YouTube', slug: 'youtube', kind: 'direct', active: true,
                   templates: { 'default' => 'https://www.youtube.com/embed/%{source_key}' })
  end
  let!(:film) do
    create(:entry, list: list, name: 'Blade Runner', year: 1982, length: 117,
                   trailer: 'https://www.youtube.com/watch?v=aaaaaaaaaaa')
  end

  def playing
    response.body[%r{youtube\.com/embed/([\w-]{11})}, 1]
  end

  it 'plays a trailer and offers the film it belongs to' do
    sign_in user
    get trailers_path

    expect(response).to be_successful
    expect(playing).to eq('aaaaaaaaaaa')
    expect(response.body).to include('Blade Runner').and include('1982 · 1 hr 57 min')
    expect(response.body).to include(watch_entry_path(film))
  end

  # The player says when a trailer ends, and the page asks this same address for the next.
  it 'asks the page itself for the next trailer' do
    sign_in user
    get trailers_path

    expect(response.body).to include(%(data-trailer-reel-url-value="#{trailers_path}"))
    expect(response.body).to include('trailer-reel:next@document->cinema-navigation#moveFromEvent')
  end

  it 'does not play the same trailer twice running' do
    create(:entry, list: list, name: 'Alien', trailer: 'https://www.youtube.com/watch?v=bbbbbbbbbbb')
    sign_in user

    get trailers_path
    first = playing
    get trailers_path

    expect(playing).not_to eq(first)
  end

  it 'records nothing about the viewer' do
    sign_in user

    expect { get trailers_path }.not_to change(UserEntry, :count)
  end

  it 'says so when there is nothing to play' do
    film.update!(trailer: nil)
    sign_in user

    get trailers_path

    expect(response).to be_successful
    expect(response.body).to include('No trailers')
  end

  describe 'a visitor with no account' do
    it 'is let in when the site is open to watching' do
      AppSetting.update_access_mode!('open')

      get trailers_path

      expect(response).to be_successful
      expect(playing).to eq('aaaaaaaaaaa')
    end

    it 'is sent to sign in when it is not' do
      AppSetting.update_access_mode!('secure')

      get trailers_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
