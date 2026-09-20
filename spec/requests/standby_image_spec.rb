require 'rails_helper'

# The "Please stand by" card, and the one thing about it that has to stay true.
#
# The Cloudinary gem is configured with `enhance_image_tag` (config/cloudinary.yml, all
# three environments), which replaces Rails' `image_tag` app-wide and rewrites the source
# before Rails sees it. A local filename came back prefixed -- `please_stand_by.png` as
# `shared/please_stand_by.png`, and `/images/please_stand_by.png` as
# `shared/images/please_stand_by.png` -- neither of which is in any asset path, so
# Sprockets raised AssetNotFound and took the whole cable page down with it. The card is
# rendered on every programme whether or not it is ever uncovered, so every channel was
# a 500.
#
# The suite did not catch it, which is the other half of the lesson: asset resolution in
# the test environment does not raise on a name it cannot place, so a request spec that
# only checks the response was successful stays green while production is down. So this
# asserts the markup itself.
RSpec.describe 'The stand-by image', :needs_provider, type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  # Every other reference to this file in the app is a plain <img> on the public path, and
  # that is the point: it goes nowhere near the pipeline, so nothing can rewrite it.
  it 'is referenced by its public path, not through the asset pipeline' do
    channel = create(:list, user: user, name: 'Late Night', default: true)
    create(:entry, list: channel, position: 1, media: 'movie', imdb: 'tt1', length: 90)
    CableSchedule.build_day!(channel, CableSchedule.today)

    get cable_channel_path(channel)

    expect(response).to be_successful
    expect(response.body).to include('src="/images/please_stand_by.png"')
  end

  # A guard against the whole class of it coming back, in either of the two places that
  # draw this file. `image_tag` is what breaks; a bare `<img>` is what works.
  it 'is never drawn with image_tag anywhere in the views' do
    offenders = Rails.root.glob('app/views/**/*.erb').select { |view|
      # The call itself, not a comment about it -- the views that were fixed explain the
      # trap in prose, and those explanations name both halves of it.
      view.read.match?(/image_tag\s+['"][^'"]*please_stand_by/)
    }.map { |view| view.relative_path_from(Rails.root).to_s }

    expect(offenders).to be_empty
  end
end
