# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Where the player got to', type: :model do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }
  # 100 minutes, so the completion mark lands on a round 5,700 seconds.
  let(:entry) { create(:entry, list: list, media: 'movie', length: 100) }
  let(:user_entry) { user.user_entry_for!(entry) }

  describe '#record_progress!' do
    it 'records where the player had reached' do
      user_entry.record_progress!(742.5)

      expect(user_entry.reload.player_progress).to eq(742.5)
    end

    it 'leaves a film stopped early unwatched' do
      user_entry.record_progress!(600)

      expect(user_entry.reload).not_to be_completed
    end

    # The last stretch of a film is credits, so somebody who stops there has seen it.
    it 'ticks the film off once it is far enough through' do
      user_entry.record_progress!(5_700)

      expect(user_entry.reload).to be_completed
    end

    it 'dates the completion from the watch rather than leaving it blank' do
      user_entry.record_progress!(5_700)

      expect(user_entry.reload.completed_at).to be_within(5.seconds).of(Time.current)
      expect(user_entry.last_watched_at).to be_within(5.seconds).of(Time.current)
    end

    # The player says so itself when the video ends, which is the only signal that works
    # for anything the catalogue has no runtime for.
    it 'ticks the film off when the player says it finished' do
      user_entry.record_progress!(120, finished: true)

      expect(user_entry.reload).to be_completed
    end

    it 'falls back to the duration the player reports when the entry has no runtime' do
      entry.update!(length: nil)

      user_entry.record_progress!(5_700, duration: 6_000)

      expect(user_entry.reload).to be_completed
    end

    it 'leaves a film alone when nothing knows how long it is' do
      entry.update!(length: nil)

      user_entry.record_progress!(5_700)

      expect(user_entry.reload).not_to be_completed
    end

    # Somebody who un-ticks a film they have seen and then scrubs through it should not
    # have that undone by the player.
    it 'never un-ticks a film' do
      user_entry.mark_completed!

      user_entry.record_progress!(30)

      expect(user_entry.reload).to be_completed
    end

    it 'does not re-date a film that was already watched' do
      user_entry.update!(completed: true, completed_at: 3.years.ago)
      was = user_entry.completed_at

      user_entry.record_progress!(5_700)

      expect(user_entry.reload.completed_at).to be_within(1.second).of(was)
    end

    # The channel warmed in the background plays while it waits its turn, so by the time
    # somebody flips to it, it can already be past the point that counts as watched --
    # without anybody having seen a frame of it.
    context 'when the film got there with nobody in front of it' do
      it 'still records where it reached' do
        user_entry.record_progress!(5_700, unattended: true)

        expect(user_entry.reload.player_progress).to eq(5_700)
      end

      it 'does not call that watched' do
        user_entry.record_progress!(5_700, unattended: true)

        expect(user_entry.reload).not_to be_completed
      end

      # Not even the player's own word for it: it ended while the room was empty.
      it 'does not call it watched when the player says it finished' do
        user_entry.record_progress!(5_900, finished: true, unattended: true)

        expect(user_entry.reload).not_to be_completed
      end

      # Once somebody is actually there, the ordinary rule applies again.
      it 'counts the next position that somebody was present for' do
        user_entry.record_progress!(5_700, unattended: true)
        user_entry.record_progress!(5_710)

        expect(user_entry.reload).to be_completed
      end
    end

    # The player has reported a negative position after a seek to the very start.
    it 'refuses a position before the beginning' do
      user_entry.record_progress!(-12)

      expect(user_entry.reload.player_progress).to eq(0)
    end
  end

  describe '#resume_position' do
    it 'is nil for an entry nobody has played' do
      expect(user_entry.resume_position).to be_nil
    end

    it 'is where the player stopped' do
      user_entry.record_progress!(742.5)

      expect(user_entry.resume_position).to eq(742.5)
    end

    # A film watched to the end reports back a position in its own credits. Resuming there
    # means pressing play and watching it finish.
    it 'starts a finished film again rather than resuming its credits' do
      user_entry.record_progress!(5_900)

      expect(user_entry.resume_position).to be_nil
    end

    it 'resumes a rewatch stopped part way through' do
      user_entry.record_progress!(5_900)
      user_entry.record_progress!(400)

      expect(user_entry.resume_position).to eq(400)
    end
  end

  # UserEntry holds one position per entry, not one per episode, so a position saved
  # against episode 4 would drop the viewer forty minutes into episode 5.
  describe 'a series moving to the next episode' do
    let(:series) { create(:entry, list: list, media: 'series', name: 'A Show', length: 45) }
    let!(:first) { Subentry.create!(entry: series, season: '1', episode: '1', name: 'Pilot') }
    let!(:second) { Subentry.create!(entry: series, season: '1', episode: '2', name: 'Second') }

    it 'starts the new episode from the beginning' do
      user.user_entry_for!(series).update!(player_progress: 1_200)
      position = UserEntryPosition.find_or_create_for(user, series)

      position.update_to_subentry!(second)

      expect(user.user_entry_for(series).reload.player_progress).to be_nil
    end

    it 'leaves the position alone when the episode has not changed' do
      user.user_entry_for!(series).update!(player_progress: 1_200)
      position = UserEntryPosition.find_or_create_for(user, series)

      position.update_to_subentry!(position.current_subentry)

      expect(user.user_entry_for(series).reload.player_progress).to eq(1_200)
    end
  end
end
