require 'rails_helper'

# Entry#resolved_source and #eligible_sources ask for the active imdb providers once per
# entry, and a channel page renders ~1,200 entries. Rails' query cache hides some of that,
# but any write in the request drops the cache and every lookup becomes a query again --
# which is exactly what a page that writes while it renders does.
RSpec.describe 'Source lookup memoization' do
  let(:list) { create(:list) }

  def source_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      next if payload[:cached] || payload[:name].to_s =~ /SCHEMA|TRANSACTION/

      count += 1 if payload[:sql] =~ /FROM "sources"/
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscriber)
    count
  end

  before do
    Source.delete_all
    Current.reset
    @provider = Source.create!(name: 'Primary', kind: 'imdb', active: true, position: 1,
                               templates: { 'movie' => 'https://p.test/%{imdb}' })
  end

  it 'reads the providers once however many entries ask' do
    entries = Array.new(12) { |i| create(:entry, list: list, position: i + 1, name: "E#{i}", media: 'movie', imdb: "tt#{i}") }

    queries = source_queries { entries.each(&:resolved_source) }

    expect(queries).to eq(1)
  end

  it 'shares the memo between resolved_source and eligible_sources' do
    entry = create(:entry, list: list, position: 1, media: 'movie', imdb: 'tt1')

    queries = source_queries do
      entry.resolved_source
      entry.eligible_sources
    end

    expect(queries).to eq(1)
  end

  it 'survives a write elsewhere dropping the query cache' do
    entries = Array.new(6) { |i| create(:entry, list: list, position: i + 1, name: "W#{i}", media: 'movie', imdb: "tt#{i}") }

    queries = source_queries do
      entries.each do |entry|
        entry.touch # a write, which clears Rails' query cache
        entry.resolved_source
      end
    end

    expect(queries).to eq(1)
  end

  describe 'invalidation' do
    it 'sees a provider added later in the same request' do
      expect(Source.default_imdb).to eq(@provider)

      added = Source.create!(name: 'Earlier', kind: 'imdb', active: true, position: 0,
                             templates: { 'movie' => 'https://q.test/%{imdb}' })

      expect(Source.default_imdb).to eq(added)
    end

    it 'sees a provider deactivated in the same request' do
      expect(Source.default_imdb).to eq(@provider)

      @provider.update!(active: false)

      expect(Source.default_imdb).to be_nil
    end
  end
end
