require 'rails_helper'

# Voting on what to watch: one screen puts up a shortlist and shows a QR code, everyone
# else scans it and taps one on their phone. The people voting have no account and are
# never asked for anything -- a device is known only by a token in its own cookie.
RSpec.describe 'Voting on a channel', :needs_provider, type: :request do
  let(:host) { create(:user) }
  let(:list) { create(:list, user: host, name: 'Friday') }

  before { %w[Alien Arrival Solaris].each_with_index { |n, i| create(:entry, list: list, name: n, position: i + 1) } }

  describe 'the room screen' do
    before { sign_in host }

    it 'is reachable from the channel' do
      get list_path(list)

      expect(response.body).to include('fa-check-to-slot')
      expect(response.body).to include(list_vote_path(list))
    end

    it 'shows a scannable code pointing back at itself' do
      get list_vote_path(list)

      expect(response.body).to include('<svg')
      expect(response.body).to include(list_vote_url(list))
    end

    it 'puts up as many as it is asked for' do
      post list_vote_path(list), params: { count: 2 }

      expect(list.vote_sessions.sole.vote_options.count).to eq(2)
    end

    it 'refuses a number that is not a shortlist' do
      post list_vote_path(list), params: { count: 99 }

      expect(list.vote_sessions.sole.vote_options.count).to eq(3) # every entry there is
    end

    it 'replaces the round when it draws again' do
      post list_vote_path(list), params: { count: 2 }
      post list_vote_path(list), params: { count: 3 }

      expect(list.vote_sessions.count).to eq(1)
      expect(list.vote_sessions.sole.vote_options.count).to eq(3)
    end

    it 'takes one off the ballot' do
      post list_vote_path(list), params: { count: 3 }
      option = list.vote_sessions.sole.vote_options.first

      delete option_list_vote_path(list, option_id: option.id)

      expect(list.vote_sessions.sole.vote_options.count).to eq(2)
    end
  end

  describe 'a phone that scanned the code' do
    before do
      sign_in host
      post list_vote_path(list), params: { count: 3 }
      sign_out host
    end

    let(:session) { list.vote_sessions.sole }

    it 'sees the ballot without an account' do
      get list_vote_path(list)

      expect(response).to be_successful
      expect(response.body).to include('Alien').or include('Arrival').or include('Solaris')
    end

    it 'votes without one either' do
      option = session.vote_options.first

      post cast_list_vote_path(list, option_id: option.id)

      expect(session.votes.count).to eq(1)
      expect(session.votes.sole.vote_option).to eq(option)
    end

    it 'changes its mind rather than voting twice' do
      first, second = session.vote_options.first(2)

      post cast_list_vote_path(list, option_id: first.id)
      post cast_list_vote_path(list, option_id: second.id)

      expect(session.votes.count).to eq(1)
      expect(session.votes.sole.vote_option).to eq(second)
    end

    it 'cannot put a shortlist up' do
      expect { post list_vote_path(list), params: { count: 2 } }.not_to change { list.vote_sessions.count }
    end

    it 'cannot close the round' do
      post close_list_vote_path(list)

      expect(session.reload).to be_open
    end
  end

  describe 'ending it' do
    let(:session) { list.vote_sessions.sole }

    before do
      sign_in host
      post list_vote_path(list), params: { count: 3 }
    end

    it 'names what won and offers to play it' do
      winner = session.vote_options.second
      session.vote_for(winner, 'phone-a')
      session.vote_for(winner, 'phone-b')
      session.vote_for(session.vote_options.first, 'phone-c')

      post close_list_vote_path(list)
      get list_vote_path(list)

      expect(session.reload).not_to be_open
      expect(response.body).to include('Winner')
      expect(response.body).to include(winner.entry.name)
      expect(response.body).to include(watch_entry_path(winner.entry))
    end

    it 'says so when nobody voted' do
      post close_list_vote_path(list)
      get list_vote_path(list)

      expect(response.body).to include('Nobody voted')
    end

    it 'turns away a vote once it has closed' do
      post close_list_vote_path(list)

      post cast_list_vote_path(list, option_id: session.vote_options.first.id)

      expect(session.votes).to be_empty
    end
  end

  describe 'the tally' do
    let(:session) { VoteSession.open_for(list, 3) }

    it 'ranks by votes and keeps ballot order through a tie' do
      first, second, third = session.vote_options.to_a
      session.vote_for(third, 'a')
      session.vote_for(second, 'b')

      expect(session.standings.map { |option, count| [option.entry.name, count] })
        .to eq([[second.entry.name, 1], [third.entry.name, 1], [first.entry.name, 0]])
    end

    it 'has no winner with no votes' do
      expect(session.winner).to be_nil
    end
  end
end
