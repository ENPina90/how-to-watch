# Dart Sass compiles app/assets/stylesheets/application.scss to app/assets/builds, which
# Sprockets then serves and digests. Unlike sassc-rails there is no Sprockets involvement
# during compilation, so external imports need explicit load paths.
Rails.application.config.dartsass.builds = {
  "application.scss" => "application.css"
}

Rails.application.config.dartsass.build_options = [
  "--style=compressed",
  "--no-source-map",
  # @import is deprecated in Dart Sass in favour of @use. Bootstrap 5.2 and
  # font-awesome-sass still use it, so silence the noise until those move.
  "--quiet-deps",
  "--silence-deprecation=import",
  # Bootstrap's and Font Awesome's Sass sources, vendored into the repo. They used to be
  # read out of node_modules, which meant the stylesheet could only be built where
  # `yarn install` had run in the same filesystem as `assets:precompile` -- true of one
  # Railway builder and not the other, so the worker's build broke the day node_modules
  # stopped being committed. See vendor/sass/README.md.
  "--load-path=#{Rails.root.join('vendor/sass')}"
]
