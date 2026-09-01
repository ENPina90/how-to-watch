require 'rails_helper'

RSpec.describe 'The Action Cable pubsub adapter' do
  # The redis gem was on 6.x while Action Cable's adapter declares `>= 4, < 6`. Everything
  # looked healthy -- the socket upgraded, the subscription took, the broadcast was logged
  # -- and then every publish raised Gem::LoadError, so nothing was ever delivered. Loading
  # the adapter is the cheapest way to notice that a bundle update has broken it again.
  %w[development production].each do |env|
    it "loads in #{env} under the gems this app actually bundles" do
      adapter = Rails.application.config_for(:cable, env: env)[:adapter]

      expect { require "action_cable/subscription_adapter/#{adapter}" }.not_to raise_error
    end
  end

  # Development needs no Redis running: Active Job is :async here too, so a fresh checkout
  # starts and a watch party works with nothing installed.
  it 'needs nothing running in development' do
    adapter = Rails.application.config_for(:cable, env: 'development')[:adapter]

    expect(adapter).to eq('async')
  end
end
