require 'rails_helper'

# The guide draws every channel on the dial across a two-day window. It used to ask the
# database whether each channel's each day was laid out, one `exists?` at a time, and read
# the dial itself once per day -- so the cost of drawing the grid grew with the dial before
# a single row was rendered. `ensure_days!` answers all of it in one query.
#
# The sibling of list_show_queries_spec and list_index_queries_spec: the point is that the
# count stays flat, not what the number is.
RSpec.describe 'The cable guide', type: :request do
  let(:user) { create(:user) }

  let!(:provider) do
    Source.create!(name: 'Primary', kind: 'imdb', active: true, position: 1,
                   templates: { 'movie' => 'https://p.test/movie?imdb=%{imdb}' })
  end

  before { sign_in user }

  def build_dial(count)
    List.where(default: true).find_each { |list| list.update_columns(default: false) }

    count.times do |i|
      channel = create(:list, user: user, provider: provider, default: true, name: "Channel #{count}-#{i}")
      3.times do |j|
        create(:entry, list: channel, name: "Programme #{count}-#{i}-#{j}", media: 'movie',
                       length: 90, position: j + 1, imdb: "tt#{count}#{i}#{j}", stream: true)
      end
      CableSchedule.add_channel!(channel)
    end
  end

  def queries_for(path, matching: nil)
    get path
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      next if payload[:cached] || payload[:name].to_s =~ /SCHEMA|TRANSACTION/

      count += 1 if matching.nil? || payload[:sql] =~ matching
    end
    get path
    ActiveSupport::Notifications.unsubscribe(subscriber)
    count
  end

  it 'does not grow with the number of channels' do
    build_dial(2)
    small = queries_for('/cable/guide')

    build_dial(6)
    expect(queries_for('/cable/guide')).to eq(small)
  end

  it 'checks the whole dial for laid-out days without a query per channel' do
    build_dial(2)
    small = queries_for('/cable/guide', matching: /FROM "cable_slots"/)

    build_dial(6)

    expect(queries_for('/cable/guide', matching: /FROM "cable_slots"/)).to eq(small)
  end

  it 'reads the dial the same number of times whatever the window holds' do
    build_dial(2)
    small = queries_for('/cable/guide', matching: /FROM "lists" WHERE "lists"\."default"/)

    build_dial(6)

    expect(queries_for('/cable/guide', matching: /FROM "lists" WHERE "lists"\."default"/)).to eq(small)
  end

  it 'still draws every channel on the dial' do
    build_dial(3)

    get '/cable/guide'

    expect(response).to be_successful
    List.where(default: true).find_each do |channel|
      expect(response.body).to include(channel.name)
    end
  end
end
