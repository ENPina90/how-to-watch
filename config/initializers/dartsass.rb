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
  # `@import "bootstrap/scss/bootstrap"`
  "--load-path=#{Rails.root.join('node_modules')}",
  # `@import "font-awesome"` ships inside the font-awesome-sass gem
  "--load-path=#{Gem.loaded_specs['font-awesome-sass'].gem_dir}/assets/stylesheets"
]
