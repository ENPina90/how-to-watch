require 'rails_helper'

# Each card on the index shows the entry the user would resume plus its poster. Both were
# resolved inside the view, once per card, so the landing page cost two queries per list
# on top of the fixed ones -- and a list appearing in two sections paid twice.
RSpec.describe 'The lists index', :needs_provider, type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def build_lists(count)
    List.where(user: user).destroy_all
    count.times do |i|
      list = create(:list, user: user, name: "List #{count}-#{i}")
      create(:entry, list: list, position: 1, name: "Entry #{count}-#{i}")
    end
  end

  def queries_for(path, matching: nil)
    get path
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      next if payload[:name].to_s =~ /SCHEMA|TRANSACTION/

      count += 1 if matching.nil? || payload[:sql] =~ matching
    end
    get path
    ActiveSupport::Notifications.unsubscribe(subscriber)
    count
  end

  it 'loads posters in one query, not one per card' do
    build_lists(9)

    expect(queries_for(lists_path, matching: /FROM "active_storage_attachments"/)).to be <= 2
  end

  it 'costs at most one query per extra list' do
    build_lists(3)
    few = queries_for(lists_path)

    build_lists(12)
    many = queries_for(lists_path)

    # current_entry still runs per list (an unordered list picks a random incomplete
    # entry), but it is a lookup on index_entries_on_list_id_and_position.
    expect(many - few).to be <= 9
  end

  it 'still points each card at the entry the user would resume' do
    build_lists(2)
    entries = List.where(user: user).filter_map { |list| list.current_entry(user) }
    expect(entries.count).to eq(2)

    get lists_path

    expect(response).to be_successful
    entries.each { |entry| expect(response.body).to include(watch_entry_path(entry)) }
  end

  it 'resolves a list appearing in two sections only once' do
    build_lists(1)
    list = List.where(user: user).first
    entry = list.entries.first
    entry.mark_completed_by!(user) # puts the list in Recently Watched as well as Your Lists

    get lists_path

    expect(response).to be_successful
  end
end
