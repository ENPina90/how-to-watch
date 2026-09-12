# frozen_string_literal: true

require 'rails_helper'

# The eye in the player's ring is drawn from the viewer's UserEntry, and the page it sits on
# is not rendered again while a film plays on it. Sitting an episode out to the end left it
# hollow until the viewer navigated somewhere, which reads as the app not having noticed.
RSpec.describe 'The watched eye', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  let(:entry) { create(:entry, list: list, name: 'Gladiator', length: 100) }

  before { sign_in user }

  # 100 minutes at the completion fraction is 5700 seconds.
  def report(seconds, finished: false)
    post progress_entry_path(entry),
         params: { progress: seconds, duration: 6000, finished: finished },
         headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
  end

  it 'answers the report that crosses the mark with the eye redrawn' do
    report(5800)

    expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    expect(response.body).to include(%(target="completed-#{entry.id}"))
    expect(response.body).to include('fa-solid fa-2x fa-eye')
    expect(response.body).to include('Mark as unwatched')
  end

  it 'says so for the player reporting the film over' do
    report(10, finished: true)

    expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    expect(response.body).to include('Mark as unwatched')
  end

  # Called on every pause and every seek. A stream per report would be the card re-rendered
  # twelve times a minute to say what it already says.
  it 'says nothing about a report that changes nothing' do
    report(60)

    expect(response).to have_http_status(:no_content)
  end

  it 'says nothing about a second report past the mark' do
    report(5800)
    report(5850)

    expect(response).to have_http_status(:no_content)
  end

  # The position is still recorded either way -- answering with markup is the only thing
  # that changed here.
  it 'records the position whichever answer it gives' do
    report(60)

    expect(user.user_entry_for(entry).player_progress).to eq(60)
    expect(user.user_entry_for(entry)).not_to be_completed
  end

  # A player warmed in the background has been running with nobody in front of it, so
  # nothing it reports is somebody watching -- and there is no eye to flip.
  it 'stays quiet for a player nobody was watching' do
    post progress_entry_path(entry),
         params: { progress: 5800, duration: 6000, unattended: true },
         headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

    expect(response).to have_http_status(:no_content)
    expect(user.user_entry_for(entry)).not_to be_completed
  end
end
