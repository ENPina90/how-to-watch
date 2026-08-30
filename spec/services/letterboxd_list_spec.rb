# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LetterboxdList do
  let(:user) { create(:user, username: 'testmember', letterboxd_enabled: true) }
  let(:body) { Rails.root.join('spec/fixtures/letterboxd/diary.xml').read }

  before do
    stub_request(:get, 'https://letterboxd.com/testmember/rss/').to_return(status: 200, body: body)
    # The feed carries TMDB ids only; the sync resolves IMDb ids so entries are playable.
    stub_request(:get, %r{api\.themoviedb\.org/3/movie/1171145})
      .to_return(status: 200, body: { imdb_id: 'tt1111111' }.to_json)
    stub_request(:get, %r{api\.themoviedb\.org/3/movie/12345})
      .to_return(status: 200, body: { imdb_id: 'tt2222222' }.to_json)
  end

  describe '#sync!' do
    it 'creates the channel on the first run' do
      described_class.new(user).sync!

      channel = user.lists.find_by(letterboxd: true)
      expect(channel.name).to eq("Testmember's Letterbox")
      expect(channel).to be_private
      # Ratings come from the diary, so the in-app review prompt has nothing to ask.
      expect(channel.reviewable).to be false
    end

    it 'imports a movie per diary entry, with its score' do
      result = described_class.new(user).sync!

      entries = user.lists.find_by(letterboxd: true).entries
      expect(entries.count).to eq(2)
      expect(result.created).to eq(2)

      crime = entries.find_by(tmdb: '1171145')
      expect(crime).to have_attributes(name: 'Crime 101', year: 2026, media: 'movie', letterboxd_score: 3.5)
    end

    it 'keeps the film slug, which is the only URL the review prompt accepts' do
      described_class.new(user).sync!

      expect(user.lists.find_by(letterboxd: true).entries.find_by(tmdb: '1171145').letterboxd_slug)
        .to eq('crime-101')
    end

    it 'backfills the IMDb id the feed does not carry, so entries are playable' do
      described_class.new(user).sync!

      expect(user.lists.find_by(letterboxd: true).entries.find_by(tmdb: '1171145').imdb).to eq('tt1111111')
    end

    it 'marks each film watched on the date the diary gives, not the date of the sync' do
      described_class.new(user).sync!

      entry = user.lists.find_by(letterboxd: true).entries.find_by(tmdb: '1171145')
      user_entry = user.user_entry_for(entry)

      expect(user_entry).to be_completed
      expect(user_entry.completed_at.to_date).to eq(Date.new(2026, 8, 28))
    end

    it 'leaves an unrated watch with no score rather than a zero' do
      described_class.new(user).sync!

      expect(user.lists.find_by(letterboxd: true).entries.find_by(tmdb: '12345').letterboxd_score).to be_nil
    end

    # The weekly refresh re-reads the whole window every time, so this runs constantly.
    it 'adds nothing on a second run over the same diary' do
      described_class.new(user).sync!
      expect { described_class.new(user).sync! }
        .not_to change { Entry.count }
    end

    it 'picks up a score that changed on Letterboxd' do
      described_class.new(user).sync!
      entry = user.lists.find_by(letterboxd: true).entries.find_by(tmdb: '1171145')
      entry.update!(letterboxd_score: 1.0)

      described_class.new(user).sync!

      expect(entry.reload.letterboxd_score).to eq(3.5)
    end

    it 'does nothing for a user who has not opted in' do
      user.update_column(:letterboxd_enabled, false)

      expect(described_class.new(user).sync!.total).to eq(0)
      expect(user.lists.find_by(letterboxd: true)).to be_nil
    end
  end

  describe '#remove!' do
    it 'deletes the channel and its entries' do
      described_class.new(user).sync!

      expect { described_class.new(user).remove! }
        .to change { user.lists.where(letterboxd: true).count }.from(1).to(0)
      expect(Entry.where(list_id: nil)).to be_empty
    end

    it 'is harmless when there is no channel' do
      expect { described_class.new(user).remove! }.not_to raise_error
    end
  end

  # The channel is found by its flag so that renaming it does not strand it -- disabling
  # the feature still has to find exactly this channel to delete.
  it 'finds a renamed channel' do
    described_class.new(user).sync!
    user.lists.find_by(letterboxd: true).update!(name: 'Something else entirely')

    expect(described_class.new(user).list.name).to eq('Something else entirely')
  end
end
