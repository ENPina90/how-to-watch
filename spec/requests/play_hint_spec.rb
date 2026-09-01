require 'rails_helper'

RSpec.describe 'The play hint on the player page' do
  let(:user)  { create(:user) }
  let(:list)  { create(:list, user: user) }
  let(:entry) { create(:entry, list: list) }

  before { sign_in user }

  # vidsrc will not build its player until someone clicks the button inside its own frame,
  # so the hint is the only thing telling a viewer that a black frame is waiting for them.
  it 'appears on a provider that gates playback behind its own click' do
    Source.create!(name: 'vidsrc.ru', slug: 'vidsrc-embed.ru', kind: 'imdb', active: true,
                   position: 1, autoplay_param: 'autoplay',
                   templates: { 'movie' => 'https://vidsrc-embed.ru/embed/movie?imdb=%{imdb}' })

    get watch_entry_path(entry, channel: list.id)

    expect(response.body).to include('Press play to start')
  end

  # Drive plays on its own, and a hint over something already playing would be a lie.
  it 'stays off a provider that starts by itself' do
    drive = Source.create!(name: 'Google Drive', slug: 'google-drive', kind: 'direct',
                           active: true, position: 1,
                           templates: { 'default' => 'https://drive.google.com/file/d/%{source_key}/preview' })
    entry.update!(provider: drive, source_key: 'abc123')

    get watch_entry_path(entry, channel: list.id)

    expect(response.body).not_to include('Press play to start')
  end
end
