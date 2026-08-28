require 'rails_helper'

# Up Next suggests something to watch. It used to sample the whole list, so it offered
# entries the user had already finished; the page then narrows the same pool to whatever
# the section filter has left in range, which only the browser knows about.
RSpec.describe 'Up Next on a list', :needs_provider, type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, user: user) }

  before { sign_in user }

  def suggested_names
    box = response.body[/data-randomize-target="picks".*?<\/div>/m]
    box.to_s.scan(%r{<a[^>]*href="#\d+"[^>]*>([^<]+)</a>}m).flatten.map(&:strip)
  end

  it 'suggests only entries the user has not watched' do
    %w[Alien Aliens Arrival].each_with_index do |name, index|
      create(:entry, list: list, name: name, position: index + 1)
    end
    list.entries.where(name: %w[Alien Aliens]).each { |entry| entry.mark_completed_by!(user) }

    get list_path(list)

    expect(suggested_names).to eq(['Arrival'])
  end

  it 'suggests nothing when everything is watched' do
    create(:entry, list: list, name: 'Alien', position: 1).mark_completed_by!(user)

    get list_path(list)

    expect(suggested_names).to be_empty
    expect(response.body).to include('Nothing unwatched here')
  end

  # The suggestion scrolls to the card, and the page matches the two up by that id when it
  # decides which picks are still in range.
  it 'anchors a suggestion to its card' do
    entry = create(:entry, list: list, name: 'Arrival', position: 1)

    get list_path(list)

    expect(response.body).to match(%r{<a[^>]*href="##{entry.id}"[^>]*>\s*Arrival\s*</a>}m)
    expect(response.body).to include(%(<div class="grid-card" id="#{entry.id}">))
  end

  # Pick for me goes to the player instead, and an undefined href would resolve against
  # the current URL -- which is how a broken pick turned into GET /lists/undefined.
  it 'sends Pick for me to the entry the card links to' do
    entry = create(:entry, list: list, name: 'Arrival', position: 1)

    get list_path(list)

    expect(response.body).to include(%(href="#{watch_entry_path(entry)}"))
  end
end
