# frozen_string_literal: true

require 'rails_helper'

# The reels that fill the gap between programmes on /cable. They are somebody else's videos
# on somebody else's service, so the page exists as much to find out whether one still plays
# as to edit the row.
RSpec.describe 'Managing commercial reels', type: :request do
  let(:admin) { create(:user, :admin) }

  let!(:youtube) do
    Source.create!(name: 'YouTube', slug: 'youtube', kind: 'direct', active: true, position: 1,
                   templates: { 'default' => 'https://www.youtube-nocookie.com/embed/%{source_key}' })
  end

  def reel(label: '1987', starts: 1987, ends: 1987, id: 'abc123', seconds: 1800)
    CommercialReel.create!(label: label, starts_year: starts, ends_year: ends,
                           youtube_id: id, duration_seconds: seconds)
  end

  describe 'who can reach it' do
    it 'opens for an admin' do
      reel
      sign_in admin

      get admin_commercial_reels_path

      expect(response).to be_successful
      expect(response.body).to include('1987')
    end

    it 'turns away a signed-in user who is not an admin' do
      sign_in create(:user)

      get admin_commercial_reels_path

      expect(response).to redirect_to(root_path)
    end

    it 'turns away a signed-out visitor, whatever the access mode' do
      AppSetting.update_access_mode!('open')

      get admin_commercial_reels_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'the listing' do
    before { sign_in admin }

    # "Arranged by the year they are associated with" -- a decade at a time, because the
    # library is one reel a year through the middle and one per era at the edges.
    it 'groups the reels by decade, in order' do
      reel(label: '1995', starts: 1995, ends: 1995, id: 'nineties')
      reel(label: '1980s', starts: 1980, ends: 1985, id: 'eighties')

      get admin_commercial_reels_path

      expect(response.body).to include('1980s', '1990s')
      expect(response.body.index('1980s')).to be < response.body.index('eighties')
      expect(response.body.index('eighties')).to be < response.body.index('nineties')
    end

    # Not an error -- `for_year` falls to the nearest era rather than to nothing -- but
    # these are the years whose adverts are least likely to belong to the film.
    it 'names the years inside its range that no reel covers' do
      reel(label: '1985', starts: 1985, ends: 1985, id: 'early')
      reel(label: '1988', starts: 1988, ends: 1988, id: 'late')

      get admin_commercial_reels_path

      expect(response.body).to include('1986, 1987')
    end

    it 'says nothing about gaps when every year is covered' do
      reel(label: '1985-88', starts: 1985, ends: 1988, id: 'whole')

      get admin_commercial_reels_path

      expect(response.body).not_to include('with no reel of its own')
    end

    # Without a runtime a break can only start in the first few minutes, so every break on
    # the channel opens with roughly the same adverts.
    it 'marks a reel with no runtime' do
      reel(label: '1991', starts: 1991, ends: 1991, id: 'untimed', seconds: nil)

      get admin_commercial_reels_path

      expect(response.body).to include('No runtime')
    end

    it 'says so when there are no reels at all' do
      get admin_commercial_reels_path

      expect(response.body).to include('commercials:seed')
    end
  end

  describe 'adding, editing and deleting' do
    before { sign_in admin }

    it 'adds a reel' do
      expect do
        post admin_commercial_reels_path, params: {
          commercial_reel: { label: '1993', starts_year: 1993, ends_year: 1993,
                             youtube_id: 'fresh1', duration_seconds: 2000 }
        }
      end.to change(CommercialReel, :count).by(1)

      expect(response).to redirect_to(admin_commercial_reels_path)
    end

    it 'renders the form again when the years run backwards' do
      post admin_commercial_reels_path, params: {
        commercial_reel: { label: 'Wrong', starts_year: 1995, ends_year: 1990, youtube_id: 'bad1' }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('must not be before the first year')
    end

    it 'edits a reel' do
      existing = reel

      patch admin_commercial_reel_path(existing), params: {
        commercial_reel: { label: '1987 (better)', starts_year: 1987, ends_year: 1987,
                           youtube_id: 'abc123' }
      }

      expect(existing.reload.label).to eq('1987 (better)')
    end

    it 'opens the edit form' do
      get edit_admin_commercial_reel_path(reel)

      expect(response).to be_successful
      expect(response.body).to include('name="commercial_reel[youtube_id]"')
    end

    it 'opens the new form' do
      get new_admin_commercial_reel_path

      expect(response).to be_successful
      expect(response.body).to include('name="commercial_reel[label]"')
    end

    # CableSlot belongs_to :break_reel, optional -- so a schedule row that pointed here
    # keeps its gap and loses only the adverts in it.
    it 'deletes a reel' do
      existing = reel

      expect { delete admin_commercial_reel_path(existing) }.to change(CommercialReel, :count).by(-1)
      expect(response).to redirect_to(admin_commercial_reels_path)
    end
  end

  # The point of the page: the same embed a break uses, at the same sort of offset.
  describe 'previewing a reel' do
    before { sign_in admin }

    it 'plays the reel through the YouTube provider, part way in' do
      get preview_admin_commercial_reel_path(reel)

      expect(response).to be_successful
      expect(response.body).to include('youtube-nocookie.com/embed/abc123')
    end

    # Never the first minute and a half, where the compilation's own titles sit -- a break
    # that opens with somebody's YouTube intro gives the whole illusion away.
    it 'starts past the titles' do
      get preview_admin_commercial_reel_path(reel)

      start = response.body[/embed\/abc123[^"]*start=(\d+)/, 1].to_i
      expect(start).to be >= CommercialReel::INTRO_SKIP
    end

    # A reel can be fine at one point and dead air at another, so a preview that always
    # opened at the same second would never show it.
    it 'rolls a different offset on a later visit' do
      existing = reel
      offsets = 8.times.map do
        get preview_admin_commercial_reel_path(existing)
        response.body[/embed\/abc123[^"]*start=(\d+)/, 1].to_i
      end

      expect(offsets.uniq.size).to be > 1
    end

    it 'simulates a break no longer than a real gap can be' do
      get preview_admin_commercial_reel_path(reel, break: 99_999)

      expect(response).to be_successful
      expect(response.body).to include(":#{format('%02d', 0)}")
    end

    it 'says so when there is no YouTube provider to build an address from' do
      youtube.update!(active: false)

      get preview_admin_commercial_reel_path(reel)

      expect(response).to be_successful
      expect(response.body).to include('no active YouTube provider')
    end

    it 'is not open to a user who is not an admin' do
      sign_in create(:user)

      get preview_admin_commercial_reel_path(reel)

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'reading the runtime off YouTube' do
    before { sign_in admin }

    it 'saves what YouTube reports' do
      existing = reel(seconds: nil)
      allow(YoutubeVideoFacts).to receive(:for).with('abc123')
        .and_return(YoutubeVideoFacts::Facts.new(duration_seconds: 2461, exists: true))

      patch fetch_duration_admin_commercial_reel_path(existing)

      expect(existing.reload.duration_seconds).to eq(2461)
    end

    # A runtime already known is better than none, so a reading that fails leaves the old
    # one alone rather than blanking it.
    it 'leaves the runtime alone when it cannot be read' do
      existing = reel(seconds: 1800)
      allow(YoutubeVideoFacts).to receive(:for)
        .and_return(YoutubeVideoFacts::Facts.new(error: 'Gone or private (HTTP 404)'))

      patch fetch_duration_admin_commercial_reel_path(existing)

      expect(existing.reload.duration_seconds).to eq(1800)
      expect(flash[:alert]).to include('Gone or private')
    end
  end

  it 'is reachable from the dashboard' do
    sign_in admin

    get admin_dashboard_path

    expect(response.body).to include(admin_commercial_reels_path)
  end
end
