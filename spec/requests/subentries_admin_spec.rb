# frozen_string_literal: true

require 'rails_helper'

# The episodes under every show, as one sortable table -- the entries table one level down.
# An episode has no provider and no stream of its own, so two of that table's columns are the
# show's here or absent, and those differences are what most of this pins down.
RSpec.describe 'The admin episodes table', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:owner) { create(:user) }

  let!(:player) do
    Source.create!(name: 'Player', kind: 'imdb', active: true, position: 1, autoplay_param: 'autoplay',
                   templates: { 'series' => 'https://p.test/tv?imdb=%{series_imdb}&s=%{season}&e=%{episode}' })
  end

  let!(:drive) do
    Source.create!(name: 'Google Drive', slug: 'google-drive', kind: 'direct', active: true, position: 2,
                   templates: { 'default' => 'https://drive.google.com/file/d/%{source_key}/preview' })
  end

  let(:channel) { create(:list, user: owner, name: 'Shows') }

  def show(name, **attrs)
    create(:entry, { list: channel, name: name, media: 'series', position: Entry.next_position(channel),
                     imdb: "tt#{name.sum}" }.merge(attrs))
  end

  def episode(parent, season, number, name: "#{parent.name} #{season}x#{number}", **attrs)
    Subentry.create!({ entry: parent, season: season, episode: number, name: name }.merge(attrs))
  end

  def row_names = response.body.scan(%r{<td class="et-name"><a [^>]*>([^<]+)</a>}).flatten

  describe 'who can reach it' do
    it 'opens for an admin' do
      episode(show('Arcane'), 1, 1, name: 'Welcome to the Playground')
      sign_in admin

      get admin_subentries_path

      expect(response).to be_successful
      expect(row_names).to eq(['Welcome to the Playground'])
    end

    it 'turns away a member who is not an admin' do
      sign_in owner

      get admin_subentries_path

      expect(response).to redirect_to(root_path)
    end

    it 'refuses an edit and a delete from a member who is not an admin' do
      target = episode(show('Arcane'), 1, 1, name: 'Pilot')
      sign_in owner

      patch admin_subentry_path(target), params: { subentry: { name: 'Hijacked' } }
      delete admin_subentry_path(target)

      expect(target.reload.name).to eq('Pilot')
    end
  end

  describe 'what a row shows' do
    before { sign_in admin }

    it 'has the show, the season and episode, and the runtime' do
      episode(show('Arcane'), 1, 4, name: 'Happy Progress Day!', length: 41)

      get admin_subentries_path

      expect(response.body).to include('Arcane', 'S01E04', '41 min')
    end

    # An episode has no provider of its own: it plays from its show's.
    it 'shows where the show plays from' do
      episode(show('Home videos', provider: drive, imdb: nil, source_key: 'abc'), 1, 1)

      get admin_subentries_path

      expect(response.body).to include('Google Drive')
    end

    it 'has no stream column, because episodes have no stream' do
      episode(show('Arcane'), 1, 1)

      get admin_subentries_path

      expect(response.body).not_to include('et-stream', '>Stream<')
    end

    it 'names an episode that arrived without one after its show, so the row has a link' do
      episode(show('Arcane'), 2, 3, name: nil)

      get admin_subentries_path

      expect(row_names).to eq(['Arcane S02E03'])
    end

    # Watched through its show's page, so the one toolbar needs the show as well as the row.
    it 'gives each row its show, and the toolbar a watch link through the show' do
      parent = show('Arcane')
      target = episode(parent, 1, 1)

      get admin_subentries_path

      expect(response.body).to include(%(id="subentry_#{target.id}" data-parent="#{parent.id}"))
      expect(response.body).to include(%(data-template="#{watch_entry_path('PARENT_ID', subentry: 'ROW_ID')}"))
      expect(response.body.scan('class="et-act"').size).to eq(1)
    end
  end

  describe 'sorting' do
    before do
      sign_in admin
      zeta = show('zeta')
      alpha = show('Alpha', provider: drive, imdb: nil, source_key: 'k')
      episode(zeta, 1, 2, name: 'Bravo', length: 30)
      episode(zeta, 1, 1, name: 'charlie', length: nil)
      episode(alpha, 2, 1, name: 'Alpha one', length: 50)
    end

    # By show, then in viewing order within it -- episodes are found by the show they are in.
    it 'sorts by show by default, in viewing order within each' do
      get admin_subentries_path

      expect(row_names).to eq(['Alpha one', 'charlie', 'Bravo'])
    end

    it 'sorts by name, ignoring case' do
      get admin_subentries_path(sort: 'name')

      expect(row_names).to eq(['Alpha one', 'Bravo', 'charlie'])
    end

    it 'sorts by season and episode' do
      get admin_subentries_path(sort: 'episode')

      expect(row_names).to eq(['charlie', 'Bravo', 'Alpha one'])
    end

    it 'puts episodes with no runtime last in both directions' do
      get admin_subentries_path(sort: 'length')
      expect(row_names.last).to eq('charlie')

      get admin_subentries_path(sort: 'length', direction: 'desc')
      expect(row_names).to eq(['Alpha one', 'Bravo', 'charlie'])
    end

    it 'sorts by the provider the show plays from' do
      get admin_subentries_path(sort: 'source')

      expect(row_names).to eq(['Alpha one', 'charlie', 'Bravo'])
    end

    it 'falls back to the default for a sort it does not know' do
      get admin_subentries_path(sort: 'id; DROP TABLE subentries')

      expect(response).to be_successful
      expect(row_names).to eq(['Alpha one', 'charlie', 'Bravo'])
    end
  end

  describe 'editing' do
    before { sign_in admin }

    let(:parent) { show('Arcane') }
    let!(:target) { episode(parent, 1, 1, name: 'Pilot', length: 44) }

    it 'answers the modal frame with a form of only what an episode owns' do
      get edit_admin_subentry_path(target), headers: { 'Turbo-Frame' => 'entry_table_edit' }

      expect(response).to be_successful
      expect(response.body).to include('<turbo-frame id="entry_table_edit">')
      %w[name season episode length].each { |field| expect(response.body).to include(%(name="subentry[#{field}]")) }
      expect(response.body).not_to include('subentry[entry_id]', 'subentry[plot]')
    end

    it 'saves, and answers with a stream that redraws only that row' do
      patch admin_subentry_path(target), params: { subentry: { name: 'Welcome', length: 45 } }, as: :turbo_stream

      expect(target.reload).to have_attributes(name: 'Welcome', length: 45)
      expect(response.body).to include(%(action="replace" target="subentry_#{target.id}"), '45 min')
    end

    # Moving an episode between shows would leave the old show's pointers aimed at it.
    it 'does not move an episode to another show' do
      other = show('Other')

      patch admin_subentry_path(target), params: { subentry: { entry_id: other.id } }, as: :turbo_stream

      expect(target.reload.entry).to eq(parent)
    end

    it 'refuses a season and episode another episode of the show already has' do
      episode(parent, 1, 2, name: 'Second')

      patch admin_subentry_path(target), params: { subentry: { episode: 2 } }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('<turbo-frame id="entry_table_edit">', 'must be unique')
      expect(target.reload.episode).to eq(1)
    end
  end

  describe 'deleting' do
    before { sign_in admin }

    it 'deletes the episode and answers with a stream that removes only that row' do
      target = episode(show('Arcane'), 1, 1)

      delete admin_subentry_path(target), as: :turbo_stream

      expect(Subentry.exists?(target.id)).to be(false)
      expect(response.body).to include(%(action="remove" target="subentry_#{target.id}"))
    end

    it 'clears a member\'s saved position on the episode rather than failing on it' do
      parent = show('Arcane')
      target = episode(parent, 1, 1)
      position = UserEntryPosition.create!(user: owner, entry: parent, current_subentry: target)

      delete admin_subentry_path(target), as: :turbo_stream

      expect(Subentry.exists?(target.id)).to be(false)
      expect(position.reload.current_subentry_id).to be_nil
    end
  end
end
