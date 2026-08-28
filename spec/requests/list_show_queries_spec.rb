require 'rails_helper'

# The Position view is the default, and it renders its own collection so entries and child
# lists can be interleaved. It used to build that from `List#all_items_by_position`, which
# reloads `entries` from scratch -- discarding the `includes(:user_entries)` in
# load_entries. The preload looked correct and did nothing: 20 entries cost 42 user_entries
# queries on the default view against 2 on a grouped one.
RSpec.describe 'The list page', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  def queries_for(path, matching: nil)
    get path # warm anything cached per-process
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      next if payload[:name].to_s =~ /SCHEMA|TRANSACTION/

      count += 1 if matching.nil? || payload[:sql] =~ matching
    end
    get path
    ActiveSupport::Notifications.unsubscribe(subscriber)
    count
  end

  describe 'query count' do
    def build_entries(count)
      list.entries.each(&:destroy)
      list.entries.reset
      count.times do |i|
        create(:entry, list: list, position: i + 1, media: 'movie', name: "Entry #{count}-#{i}")
      end
    end

    it 'does not grow with the number of entries' do
      build_entries(4)
      few = queries_for(list_path(list))

      build_entries(16)
      many = queries_for(list_path(list))

      expect(many).to eq(few)
    end

    it 'reads this user\'s tracking rows in one query, not one per entry' do
      build_entries(16)

      expect(queries_for(list_path(list), matching: /FROM "user_entries"/)).to be <= 3
    end

    it 'loads posters in one query, not one per entry' do
      build_entries(16)

      expect(queries_for(list_path(list), matching: /FROM "active_storage_attachments"/)).to be <= 2
    end

    it 'holds for a grouped view too' do
      build_entries(4)
      few = queries_for(list_path(list, criteria: 'Genre'))

      build_entries(16)
      expect(queries_for(list_path(list, criteria: 'Genre'))).to eq(few)
    end
  end

  describe 'ordering' do
    it 'interleaves entries and child lists by position' do
      create(:entry, list: list, position: 1, name: 'First')
      create(:entry, list: list, position: 3, name: 'Third')
      child = create(:list, user: user, name: 'Middle List')
      child.update!(position: 2)
      list.child_relationships.create!(child_list: child, position: 2)

      get list_path(list)

      # Scoped to the ordered list itself: the child-list nav and the sidebar's Up Next
      # both name these elsewhere on the page.
      container = response.body[/<div id="list-entries">.*/m]
      expect(container.index('First')).to be < container.index('Middle List')
      expect(container.index('Middle List')).to be < container.index('Third')
    end
  end
end
