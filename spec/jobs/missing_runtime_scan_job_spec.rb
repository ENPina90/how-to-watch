# frozen_string_literal: true

require 'rails_helper'

# Fill first, then warn: a runtime TMDB could supply should never become a card an admin has
# to act on by hand.
RSpec.describe MissingRuntimeScanJob do
  let!(:admin) { create(:user, :admin) }
  let(:list) { create(:list) }

  it 'raises no warning for a runtime TMDB filled in' do
    film = create(:entry, list: list, media: 'movie', imdb: 'tt0172495', length: nil)
    allow(RuntimeBackfill).to receive(:call) { film.update_column(:length, 155) }

    described_class.perform_now

    expect(Notification.where(kind: Notification::MISSING_RUNTIME)).to be_empty
  end

  it 'still warns about the rest when TMDB cannot be reached at all' do
    film = create(:entry, list: list, media: 'movie', imdb: 'tt0172495', length: nil)
    allow(RuntimeBackfill).to receive(:call).and_raise(KeyError, 'key not found: "TMDB_API_KEY"')

    described_class.perform_now

    expect(Notification.find_by(kind: Notification::MISSING_RUNTIME, subject: film)).to be_present
  end
end
