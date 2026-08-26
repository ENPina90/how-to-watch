require 'rails_helper'

# Every card used to carry its own review, trailer and poster-picker modal. On the
# 1,203-entry "Movies to Watch Before You Die" that was 3,610 modals, 1,203 <iframe>s and
# 1,202 identical copies of the rating script in one response -- 12.7 MB of HTML and ~2s
# of view rendering before the browser saw anything. The modals are now rendered once per
# page and told which entry they are for by the trigger that opened them.
#
# The regression is invisible in a browser (everything still works, the page is just
# enormous), so it is asserted on counts here rather than on behaviour.
RSpec.describe 'The list page payload', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user, reviewable: true) }

  before { sign_in user }

  def build_entries(count)
    @next_position ||= 0
    count.times do
      @next_position += 1
      create(:entry, list: list, position: @next_position, media: 'movie',
                     name: "Entry #{@next_position}", trailer: 'https://youtube.com/watch?v=abc')
    end
  end

  describe 'the shared modals' do
    it 'renders one of each however many entries there are' do
      build_entries(12)

      get list_path(list)

      expect(response.body.scan('id="reviewModal"').size).to eq(1)
      expect(response.body.scan('id="trailerModal"').size).to eq(1)
      expect(response.body.scan('id="posterModal"').size).to eq(1)
    end

    it 'leaves no per-entry modal ids behind' do
      build_entries(12)

      get list_path(list)

      expect(response.body).not_to match(/reviewModal\d/)
      expect(response.body).not_to include('trailerModal-')
      expect(response.body).not_to include('posterModal-')
    end

    it 'keeps one <iframe> and one rating script rather than one per entry' do
      build_entries(12)

      get list_path(list)

      expect(response.body.scan('<iframe').size).to eq(1)
      # The rating logic lives in review_modal_controller.js now; the inline copy that
      # used to be emitted once per entry is gone.
      expect(response.body.scan('function selectRating').size).to eq(0)
    end
  end

  describe 'the payload' do
    it 'does not grow with entry count the way a per-card modal does' do
      build_entries(5)
      get list_path(list)
      small = response.body.bytesize

      build_entries(15) # 20 total, 4x
      get list_path(list)
      large = response.body.bytesize

      # The cards themselves still scale, so this is not flat -- but each extra entry must
      # cost roughly a card, not a card plus three modals and a form. On list 21 in
      # development that is ~3.0 KB per entry, against ~10.6 KB before this change.
      per_entry = (large - small) / 15.0
      expect(per_entry).to be < 4_000
    end
  end

  describe 'the watch page' do
    # It shows one entry, so it keeps its own entry-specific modal (its form has turbo
    # disabled, like the rest of that page). The shared trigger in _completion_status
    # names a single id, so the two have to agree or the eye icon opens nothing.
    it 'answers the same #reviewModal trigger the list page uses' do
      entry = create(:entry, list: list, position: 1, media: 'movie', imdb: 'tt1', name: 'Sacrifice')

      get watch_entry_path(entry)

      expect(response.body.scan('id="reviewModal"').size).to eq(1)
      expect(response.body).to include(%(data-bs-target="#reviewModal"))
      expect(response.body).not_to match(/reviewModal\d/)
    end
  end

  describe 'the triggers' do
    it 'carry everything the shared review modal needs' do
      entry = create(:entry, list: list, position: 1, media: 'movie', name: 'Solaris')

      get list_path(list)

      expect(response.body).to include(%(data-bs-target="#reviewModal"))
      expect(response.body).to include(%(data-entry-name="Solaris"))
      expect(response.body).to include(%(data-review-url="#{review_entry_path(entry)}"))
      expect(response.body).to include(%(data-skip-url="#{complete_without_review_entry_path(entry)}"))
    end

    it 'carry the entry the shared poster picker should load' do
      entry = create(:entry, list: list, position: 1, media: 'movie', name: 'Stalker')

      get list_path(list)

      expect(response.body).to include(%(data-bs-target="#posterModal"))
      expect(response.body).to include(%(data-entry-id="#{entry.id}"))
    end

    it 'carry the trailer url on the card, not in a modal per card' do
      create(:entry, list: list, position: 1, media: 'movie', name: 'Mirror',
                     trailer: 'https://youtube.com/watch?v=xyz')

      get list_path(list)

      expect(response.body).to include(%(data-bs-target="#trailerModal"))
      expect(response.body).to include('data-trailer-name="Mirror"')
    end
  end
end
