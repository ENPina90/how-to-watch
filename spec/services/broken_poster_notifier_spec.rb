# frozen_string_literal: true

require 'rails_helper'

# A broken poster is a state, not an event, so the notifications have to behave like the
# expiry warnings do: raised while the poster is still broken, retired the moment it is
# fixed, and -- once dismissed -- silent until the poster actually changes.
RSpec.describe BrokenPosterNotifier do
  let!(:admin) { create(:user, :admin) }
  let(:list) { create(:list, name: 'Funny') }

  def serving(url, status: 200, content_type: 'image/jpeg')
    stub_request(:head, url).to_return(status: status, headers: { 'Content-Type' => content_type })
  end

  def notices_for(user) = Notification.where(user: user, kind: Notification::BROKEN_POSTER)

  it 'raises one notification per entry whose poster will not load' do
    create(:entry, list: list, name: 'Fantasmas', pic: 'https://img.test/gone.jpg')
    create(:entry, list: list, name: 'Ted Lasso', pic: 'https://img.test/there.jpg')
    serving('https://img.test/gone.jpg', status: 404)
    serving('https://img.test/there.jpg')

    described_class.call

    expect(notices_for(admin).pluck(:kind).size).to eq(1)
    expect(notices_for(admin).first.data['name']).to eq('Fantasmas')
  end

  it 'points the notification at the entry, so the page has somewhere to send you' do
    entry = create(:entry, list: list, name: 'Fantasmas', pic: 'https://img.test/gone.jpg')
    serving('https://img.test/gone.jpg', status: 404)

    described_class.call

    expect(notices_for(admin).first.subject).to eq(entry)
  end

  it 'retires the notification once the poster is replaced' do
    entry = create(:entry, list: list, name: 'Fantasmas', pic: 'https://img.test/gone.jpg')
    serving('https://img.test/gone.jpg', status: 404)
    described_class.call

    entry.update!(pic: 'https://img.test/fixed.jpg')
    serving('https://img.test/fixed.jpg')

    expect { described_class.call }.to change { notices_for(admin).count }.from(1).to(0)
  end

  it 'leaves a dismissed notification dismissed while the poster is the same broken one' do
    create(:entry, list: list, name: 'Fantasmas', pic: 'https://img.test/gone.jpg')
    serving('https://img.test/gone.jpg', status: 404)
    described_class.call
    notices_for(admin).first.dismiss!

    described_class.call

    expect(notices_for(admin).active).to be_empty
    expect(notices_for(admin).count).to eq(1)
  end

  # The other half of that: dismissing hides this poster, not the entry forever. Swapping in
  # a poster that is also broken is a new thing to be told about.
  it 'raises a fresh notification when the poster changes and is still broken' do
    entry = create(:entry, list: list, name: 'Fantasmas', pic: 'https://img.test/gone.jpg')
    serving('https://img.test/gone.jpg', status: 404)
    described_class.call
    notices_for(admin).first.dismiss!

    entry.update!(pic: 'https://img.test/also-gone.jpg')
    serving('https://img.test/also-gone.jpg', status: 404)
    described_class.call

    expect(notices_for(admin).active.count).to eq(1)
  end

  it 'tells nobody but the admins' do
    member = create(:user)
    create(:entry, list: list, name: 'Fantasmas', pic: 'https://img.test/gone.jpg')
    serving('https://img.test/gone.jpg', status: 404)

    described_class.call

    expect(notices_for(member)).to be_empty
  end

  it 'reports what it did, for the job log' do
    create(:entry, list: list, name: 'Fantasmas', pic: 'https://img.test/gone.jpg')
    serving('https://img.test/gone.jpg', status: 404)

    result = described_class.call

    expect(result).to have_attributes(checked: 1, broken: 1, created: 1, removed: 0)
  end
end
