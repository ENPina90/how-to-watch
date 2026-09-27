require 'rails_helper'

# The source switcher carries the same report-broken toggle as the entry card, so a dead
# provider can be flagged from the page where it turned out to be dead. It is drawn only
# for someone reportlink will accept: shown to a viewer who cannot edit the entry, the
# click would flip the icon and then flip it straight back when the PATCH was refused.
RSpec.describe 'Report broken link on the watch page', :needs_provider, type: :request do
  let(:owner)    { create(:user) }
  let(:stranger) { create(:user) }
  let(:list)     { create(:list, user: owner, default: false) }
  let(:entry)    { create(:entry, list: list, position: 1, media: 'movie', imdb: 'tt1', name: 'Owned') }

  def report_button
    response.body[/<button[^>]*source-switcher__report[^>]*>/m]
  end

  it 'offers the toggle to someone who can edit the entry' do
    sign_in owner
    get watch_entry_path(entry)

    expect(report_button).to include('data-controller="link"')
    expect(report_button).to include(%(data-link-id-value="#{entry.id}"))
    expect(report_button).to include('link-ok')
  end

  it 'starts in the reported state when the entry is already marked broken' do
    entry.update!(stream: false)
    sign_in owner
    get watch_entry_path(entry)

    expect(report_button).to include('link-broken')
  end

  it 'is not drawn for someone the action would refuse' do
    sign_in stranger
    get watch_entry_path(entry)

    expect(response).to be_successful
    expect(report_button).to be_nil
  end
end
