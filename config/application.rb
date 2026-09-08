require_relative "boot"

require "rails/all"
# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module HowToWatch
  class Application < Rails::Application
    config.generators do |generate|
      generate.assets false
      generate.helper false
      generate.test_framework :test_unit, fixture: false
    end
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Action Cable's default mount path is /cable, and it is Rack middleware -- it answers
    # that path before the router is ever consulted, so it took the whole of the /cable
    # channel surfing feature with it (a 404 on /cable, while /cable/:id routed fine).
    # The socket has no reason to own a word a person would type; the watch-party consumer
    # is told the same path explicitly in watch_party_controller.js.
    config.action_cable.mount_path = "/websocket"
  end
end
