# frozen_string_literal: true

require 'rails_helper'

# Every entry in the app as one sortable table. It reaches across every member's channels
# and deletes from any of them, so who can open it matters as much as what it shows -- and
# because it is thousands of rows long, so does what each row does and does not carry.
RSpec.describe 'The admin entries table', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:owner) { create(:user) }

  let!(:imdb_source) do
    Source.create!(name: 'Player', kind: 'imdb', active: true, position: 1, autoplay_param: 'autoplay',
                   templates: { 'movie' => 'https://p.test/movie?imdb=%{imdb}' })
  end

  let!(:drive) do
    Source.create!(name: 'Google Drive', slug: 'google-drive', kind: 'direct', active: true, position: 2,
                   templates: { 'default' => 'https://drive.google.com/file/d/%{source_key}/preview' })
  end

  let(:films) { create(:list, user: owner, name: 'Films') }
  let(:shorts) { create(:list, user: owner, name: 'Anthology') }

  def entry(name, list: films, **attrs)
    create(:entry, { list: list, name: name, position: Entry.next_position(list), imdb: "tt#{name.sum}" }.merge(attrs))
  end

  def row_names = response.body.scan(%r{<td class="et-name"><a [^>]*>([^<]+)</a>}).flatten

  describe 'who can reach it' do
    it 'opens for an admin' do
      entry('Alien')
      sign_in admin

      get admin_entries_path

      expect(response).to be_successful
      expect(row_names).to eq(['Alien'])
    end

    it 'turns away a member who is not an admin, even one whose entries are on it' do
      entry('Alien')
      sign_in owner

      get admin_entries_path

      expect(response).to redirect_to(root_path)
    end

    it 'turns away a signed-out visitor' do
      get admin_entries_path

      expect(response).to redirect_to(new_user_session_path)
    end

    # Writes too, not just the page: the verbs are reachable without the page.
    it 'refuses an edit and a delete from a member who is not an admin' do
      target = entry('Alien')
      sign_in owner

      patch admin_entry_path(target), params: { entry: { name: 'Hijacked' } }
      delete admin_entry_path(target)

      expect(target.reload.name).to eq('Alien')
    end
  end

  describe 'what a row shows' do
    before { sign_in admin }

    it 'has the channel, media, runtime and where the entry plays from' do
      entry('Alien', length: 117)

      get admin_entries_path

      expect(response.body).to include('Films', 'movie', '117 min', 'Player')
    end

    # The source column answers what the player will actually load, not the provider
    # column alone -- an entry with no provider of its own plays from its channel's.
    it 'shows an inherited provider rather than a blank' do
      films.update!(provider: drive)
      entry('Home movie', imdb: nil, source_key: 'abc')

      get admin_entries_path

      expect(response.body).to include('Google Drive')
    end

    it 'marks a working, a broken and a never-checked stream differently' do
      entry('Works', stream: true)
      entry('Broken', stream: false)
      entry('Unchecked', stream: nil)

      get admin_entries_path

      expect(response.body).to include('fa-check et-ok', 'fa-xmark et-bad', 'title="Never checked (press to mark working)"')
    end

    # The actions are one toolbar the page moves between rows, not a set per row. Per row they
    # were seven of every row's sixteen elements; this is what keeps several thousand rows light.
    it 'draws one set of row actions for the whole table, not one per row' do
      3.times { |i| entry("Film #{i}") }

      get admin_entries_path

      expect(response.body.scan('class="et-act"').size).to eq(1)
      # Aimed at a placeholder the page fills in, not at any one entry. (The layout's own
      # Log out link is a delete as well, which is why this counts the address.)
      expect(response.body.scan(%(data-template="#{admin_entry_path('ROW_ID')}")).size).to eq(1)
      expect(response.body).not_to match(%r{href="/admin/entries/\d+})
      # The rows themselves -- the layout has forms of its own elsewhere on the page.
      rows = response.body[%r{<tbody.*?</tbody>}m]
      expect(rows.scan('<tr ').size).to eq(3)
      expect(rows).not_to include('<form', 'modal', 'et-act')
    end
  end

  describe 'sorting' do
    before do
      sign_in admin
      entry('Bravo', list: films, length: 90, stream: true)
      entry('alpha', list: shorts, length: nil, stream: false)
      entry('Charlie', list: shorts, length: 30, stream: nil, provider: drive, imdb: nil, source_key: 'k')
    end

    it 'sorts by name by default, ignoring case' do
      get admin_entries_path

      expect(row_names).to eq(%w[alpha Bravo Charlie])
    end

    it 'turns round when asked' do
      get admin_entries_path(sort: 'name', direction: 'desc')

      expect(row_names).to eq(%w[Charlie Bravo alpha])
    end

    it 'sorts by channel, with name breaking the tie' do
      get admin_entries_path(sort: 'list')

      expect(row_names).to eq(%w[alpha Charlie Bravo])
    end

    # Blank runtimes are not what somebody sorting by runtime is looking for, whichever way.
    it 'puts entries with no runtime last in both directions' do
      get admin_entries_path(sort: 'length')
      expect(row_names).to eq(%w[Charlie Bravo alpha])

      get admin_entries_path(sort: 'length', direction: 'desc')
      expect(row_names).to eq(%w[Bravo Charlie alpha])
    end

    it 'sorts by the provider each entry actually plays from' do
      get admin_entries_path(sort: 'source')

      expect(row_names).to eq(%w[Charlie alpha Bravo])
    end

    it 'falls back to name for a sort it does not know, rather than erroring' do
      get admin_entries_path(sort: 'entries.id; DROP TABLE entries')

      expect(response).to be_successful
      expect(row_names).to eq(%w[alpha Bravo Charlie])
    end
  end

  describe 'editing' do
    before { sign_in admin }

    let!(:target) { entry('Alien', length: 117, stream: true) }

    it 'answers the modal frame with a form of only the fields the table shows' do
      get edit_admin_entry_path(target), headers: { 'Turbo-Frame' => 'entry_table_edit' }

      expect(response).to be_successful
      expect(response.body).to include('<turbo-frame id="entry_table_edit">')
      %w[name list_id media length stream provider_id source_key source_url].each do |field|
        expect(response.body).to include(%(name="entry[#{field}]"))
      end
      expect(response.body).not_to include('entry[plot]', 'entry[poster')
    end

    it 'saves, and answers with a stream that redraws only that row' do
      patch admin_entry_path(target), params: { entry: { length: 118 } }, as: :turbo_stream

      expect(target.reload.length).to eq(118)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include(%(action="replace" target="entry_#{target.id}"), '118 min')
    end

    # Three answers, not two: never-checked is its own state, and the cable schedule reads it
    # differently from either of the others.
    it 'sets the stream to working, broken, or back to never checked' do
      { 'false' => false, 'true' => true, '' => nil }.each do |submitted, stored|
        patch admin_entry_path(target), params: { entry: { stream: submitted } }, as: :turbo_stream
        expect(target.reload.stream).to eq(stored)
      end
    end

    it 'sets the source from a provider and a key' do
      patch admin_entry_path(target), params: { entry: { provider_id: drive.id, source_key: 'drive-file' } },
                                      as: :turbo_stream

      expect(target.reload.provider).to eq(drive)
      expect(target.source_key).to eq('drive-file')
    end

    it 'sets the source from a pasted link' do
      patch admin_entry_path(target),
            params: { entry: { source_url: 'https://drive.google.com/file/d/pasted-id/view' } }, as: :turbo_stream

      expect(target.reload.provider).to eq(drive)
      expect(target.source_key).to eq('pasted-id')
    end

    # Every other keyless entry reads NULL, so a cleared field is stored the same way.
    it 'stores a cleared source key as nothing rather than an empty string' do
      target.update!(provider: drive, source_key: 'old')

      patch admin_entry_path(target), params: { entry: { source_key: '' } }, as: :turbo_stream

      expect(target.reload.source_key).to be_nil
    end

    # The same rule as the channel page's form: the old position is a place in the old
    # channel, and keeping it would land on top of whatever holds that number in the new one.
    it 'moves an entry to the end of another channel' do
      entry('Already there', list: shorts)

      patch admin_entry_path(target), params: { entry: { list_id: shorts.id } }, as: :turbo_stream

      expect(target.reload.list).to eq(shorts)
      expect(target.position).to eq(shorts.entries.maximum(:position))
      expect(shorts.entries.where(position: target.position).count).to eq(1)
    end

    it 'refuses an invalid save and answers 422 with the form, so the modal stays open' do
      patch admin_entry_path(target), params: { entry: { name: '' } }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('<turbo-frame id="entry_table_edit">', "can&#39;t be blank")
      expect(target.reload.name).to eq('Alien')
    end
  end

  # The tick or cross in the stream column is also its switch.
  describe 'pressing a stream mark' do
    before { sign_in admin }

    it 'sets the value asked for and redraws only that row' do
      target = entry('Alien', stream: false)

      patch stream_admin_entry_path(target), params: { value: 'true' }, as: :turbo_stream

      expect(target.reload.stream).to be(true)
      expect(response.body).to include(%(action="replace" target="entry_#{target.id}"), 'fa-check et-ok', 'marked working')
    end

    it 'marks a working stream broken' do
      target = entry('Alien', stream: true)

      patch stream_admin_entry_path(target), params: { value: 'false' }, as: :turbo_stream

      expect(target.reload.stream).to be(false)
    end

    # A value, not a flip: the same press arriving twice must not undo itself.
    it 'sets the same value twice rather than toggling back' do
      target = entry('Alien', stream: false)

      2.times { patch stream_admin_entry_path(target), params: { value: 'true' }, as: :turbo_stream }

      expect(target.reload.stream).to be(true)
    end

    # Never checked is set from the edit form; a press means somebody has looked.
    it 'refuses anything but true or false' do
      target = entry('Alien', stream: true)

      patch stream_admin_entry_path(target), params: { value: '' }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_entity)
      expect(target.reload.stream).to be(true)
    end

    # One flag on a row: an unrelated validation problem on the entry must not block it.
    it 'flips an entry that would fail validation for some other reason' do
      target = entry('Alien', stream: false)
      target.update_columns(name: '')

      patch stream_admin_entry_path(target), params: { value: 'true' }, as: :turbo_stream

      expect(target.reload.stream).to be(true)
    end

    it 'refuses a member who is not an admin' do
      target = entry('Alien', stream: false)
      sign_out admin
      sign_in owner

      patch stream_admin_entry_path(target), params: { value: 'true' }

      expect(target.reload.stream).to be(false)
    end

    it 'draws each mark as something a keyboard can reach and press' do
      entry('Alien', stream: nil)

      get admin_entries_path

      expect(response.body).to include('class="et-na et-flip"', 'role="button"', 'tabindex="0"')
      expect(response.body).to include(%(data-entry-table-stream-url-value="#{stream_admin_entry_path('ROW_ID')}"))
    end
  end

  describe 'deleting' do
    before { sign_in admin }

    it 'deletes the entry and answers with a stream that removes only that row' do
      target = entry('Alien')

      delete admin_entry_path(target), as: :turbo_stream

      expect(Entry.exists?(target.id)).to be(false)
      expect(response.body).to include(%(action="remove" target="entry_#{target.id}"))
    end

    it 'deletes an entry from any member\'s channel, private ones included' do
      films.update!(private: true)
      target = entry('Private film')

      delete admin_entry_path(target), as: :turbo_stream

      expect(Entry.exists?(target.id)).to be(false)
    end
  end
end
