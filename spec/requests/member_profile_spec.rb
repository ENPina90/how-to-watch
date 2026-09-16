require 'rails_helper'

# A member's public page. The thing worth pinning down is that it is *public to members* and
# not to the internet, that its three numbers count what they say they count, and that the
# history distinguishes something watched from something merely started.
RSpec.describe 'A member profile', type: :request do
  let(:member) { create(:user, username: 'harmy') }
  let(:viewer) { create(:user) }

  describe 'who can see it' do
    it 'is not open to a signed-out visitor' do
      get member_path(member)

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'is open to any signed-in member, not only to themselves' do
      sign_in viewer

      get member_path(member)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'what it says' do
    before { sign_in viewer }

    it 'names them and says how long they have been here' do
      get member_path(member)

      expect(response.body).to include('harmy')
      expect(response.body).to include(member.created_at.strftime('%B %Y'))
    end

    # Entries have no user of their own, so "added" is a question about whose channels they
    # are in. Someone else's channel does not count towards this member's total.
    it 'counts the channels they own and the entries in them' do
      mine = create(:list, user: member)
      create(:entry, list: mine, name: 'Mine', position: 1)
      theirs = create(:list, user: viewer)
      create(:entry, list: theirs, name: 'Theirs', position: 1)

      get member_path(member)

      expect(response.body).to include('1</span>')
    end

    it 'counts what they have ticked, not what they have opened' do
      list = create(:list, user: member)
      done = create(:entry, list: list, name: 'Finished', position: 1)
      started = create(:entry, list: list, name: 'Started', position: 2)
      UserEntry.create!(user: member, entry: done, completed: true, completed_at: 1.day.ago)
      UserEntry.create!(user: member, entry: started, completed: false, last_watched_at: 2.days.ago)

      get member_path(member)

      expect(response.body).to include('Finished', 'Started')
      expect(response.body).to include('watch-history__mark--done')
      expect(response.body).to include('watch-history__mark--started')
    end

    it 'says so when there is no history yet' do
      get member_path(member)

      expect(response.body).to include('has not watched anything yet')
    end
  end

  describe 'the Letterboxd link' do
    before { sign_in viewer }

    it 'is offered when the account is linked' do
      member.update!(letterboxd_enabled: true)

      get member_path(member)

      expect(response.body).to include('https://letterboxd.com/harmy/')
    end

    it 'is absent when it is not' do
      get member_path(member)

      expect(response.body).not_to include('letterboxd.com/harmy')
    end
  end

  describe 'the ways in' do
    before { sign_in viewer }

    it 'is linked from the byline on a channel page' do
      list = create(:list, user: member, name: 'Theirs')

      get list_path(list)

      expect(response.body).to include(member_path(member))
      expect(response.body).to include('list-byline')
    end

    # The owner's name on a community card used to be text inside the link to the channel.
    # An anchor cannot hold an anchor, so making it a link meant splitting that block up.
    it 'is linked from the owner named on a community channel card' do
      # The community row is `List.discoverable_by`, which skips empty channels -- so an
      # entry is needed for the card to be drawn at all.
      theirs = create(:list, user: member, name: 'Theirs')
      create(:entry, list: theirs, name: 'Something', position: 1)

      get lists_path

      expect(response.body).to include(member_path(member))
      expect(response.body).not_to match(%r{<a[^>]*>(?:(?!</a>).)*<a }m)
    end
  end
end
