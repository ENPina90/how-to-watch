# frozen_string_literal: true

require 'rails_helper'

# An episode the player calls watched moves the series on to the next one, so opening the
# show again plays what comes after rather than what just ended. The show's own
# `completed` flag cannot drive this -- it flips once, on whichever episode finishes first
# -- so every report is judged on its own, and the page names the episode it is about.
RSpec.describe 'Moving a series on once an episode is watched', type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, ordered: true) }
  # 45-minute episodes, so the completion mark falls at 2,565 seconds. The show's own figure
  # is the whole series, and is never what an episode is judged by.
  let!(:show) { create(:entry, list: list, name: 'A Show', media: 'series', position: 1, length: 135) }
  let!(:after_show) { create(:entry, list: list, name: 'A Film', media: 'movie', position: 2, length: 100) }
  let!(:first) { show.subentries.create!(season: 1, episode: 1, name: 'Pilot', length: 45) }
  let!(:second) { show.subentries.create!(season: 1, episode: 2, name: 'Second', length: 45) }
  let!(:third) { show.subentries.create!(season: 1, episode: 3, name: 'Third', length: 45) }

  before do
    sign_in user
    show.update_user_subentry!(user, first)
    list.position_for_user!(user).update!(current_position: show.position)
  end

  def episode
    show.current_subentry_for_user(user).reload
  end

  def report(on, progress, **extra)
    post progress_entry_path(show, subentry: on.id), params: { progress: progress, **extra }
  end

  describe 'the progress report' do
    it 'moves to the next episode once this one is far enough through' do
      report(first, 2_700)

      expect(episode).to eq(second)
    end

    # The show's position belongs to the episode that just ended; the next starts at zero.
    it 'starts the next episode from the beginning' do
      report(first, 2_700)

      expect(user.user_entry_for(show).player_progress).to be_nil
    end

    it 'stays on an episode stopped part way through' do
      report(first, 600)

      expect(episode).to eq(first)
      expect(user.user_entry_for(show).player_progress).to eq(600)
    end

    it 'stays for an unattended report' do
      report(first, 2_700, unattended: 'true')

      expect(episode).to eq(first)
    end

    # The show was ticked off by the first episode; the second still moves it on.
    it 'moves on again for every episode, not only the one that ticked the show off' do
      report(first, 2_700)
      report(second, 2_700)

      expect(episode).to eq(third)
    end

    # A pause in the credits, or the last word as the page goes away, after the move.
    it 'ignores later reports about the episode it has moved on from' do
      report(first, 2_700)
      report(first, 2_800)

      expect(episode).to eq(second)
      expect(user.user_entry_for(show).player_progress).to be_nil
    end

    it 'moves the channel past the show once its last episode is watched' do
      show.update_user_subentry!(user, third)

      report(third, 2_700)

      expect(episode).to eq(third)
      expect(list.position_for_user(user).reload.current_position).to eq(after_show.position)
    end

    it 'leaves the channel on the show while episodes remain' do
      report(first, 2_700)

      expect(list.position_for_user(user).reload.current_position).to eq(show.position)
    end

    # A page rendered before the episode was named keeps working as it did.
    it 'records a report that names no episode without moving' do
      post progress_entry_path(show), params: { progress: 2_700 }

      expect(episode).to eq(first)
      expect(user.user_entry_for(show).player_progress).to eq(2_700)
    end
  end

  # The up-next card and the arrow fire after the report above has already moved the show
  # on. Stepping from the stored episode would skip one.
  describe 'stepping from the episode on screen' do
    it 'goes to the episode after the one named, not after the stored one' do
      report(first, 2_700)

      patch increment_current_entry_path(show, mode: 'watch', channel: list.id, subentry: first.id)

      expect(episode).to eq(second)
    end

    it 'goes back from the episode named' do
      show.update_user_subentry!(user, third)

      patch decrement_current_entry_path(show, mode: 'watch', channel: list.id, subentry: second.id)

      expect(episode).to eq(first)
    end

    it 'steps from the stored episode when none is named' do
      patch increment_current_entry_path(show, mode: 'watch', channel: list.id)

      expect(episode).to eq(second)
    end

    it 'ignores an episode that belongs to another show' do
      other = create(:entry, list: list, name: 'Another Show', media: 'series', position: 3)
      stranger = other.subentries.create!(season: 1, episode: 5, name: 'Elsewhere')

      patch increment_current_entry_path(show, mode: 'watch', channel: list.id, subentry: stranger.id)

      expect(episode).to eq(second)
    end
  end

  describe 'the watch page', :needs_provider do
    before { show.update!(imdb: 'tt0060028') }

    it 'names the episode on screen wherever it asks to move or reports progress' do
      show.update_user_subentry!(user, second)

      get watch_entry_path(show, channel: list.id)

      expect(response.body).to include(
        CGI.escapeHTML(progress_entry_path(show, channel: list.id, subentry: second.id)),
        CGI.escapeHTML(increment_current_entry_path(show, mode: 'watch', channel: list.id, subentry: second.id)),
        CGI.escapeHTML(decrement_current_entry_path(show, mode: 'watch', channel: list.id, subentry: second.id)),
        %(data-auto-advance-subentry-id-value="#{second.id}")
      )
    end
  end
end
