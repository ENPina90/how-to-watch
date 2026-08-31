# Vendored Sass sources

Bootstrap 5.2.3 and Font Awesome Free 6.7.2, copied verbatim from the npm packages of the
same versions. `config/initializers/dartsass.rb` puts this directory on Dart Sass's load
path, so `app/assets/stylesheets/application.scss` imports them by the same paths it always
used (`bootstrap/scss/bootstrap`, `@fortawesome/fontawesome-free/scss/...`).

## Why these are here and not in node_modules

The stylesheet used to be built against `node_modules`. That worked only where
`yarn install` had run in the same filesystem as `assets:precompile` -- which was true of
the web service's builder (Nixpacks) and not the worker's (Railpack, whose install and
build are separate layers). While `node_modules` was committed to the repo the difference
was invisible; the day it stopped being committed, every worker build failed on

    Error: Can't find stylesheet to import.
    @import "bootstrap/scss/bootstrap";

and the worker silently went on serving an older image. Vendoring makes the build depend
on nothing but the checkout, under any builder.

## Why not the RubyGems

`bootstrap` and `font-awesome-sass` exist at exactly these versions, but both declare a
runtime dependency on sassc/sassc-rails -- the deprecated native extension this app
deliberately dropped in favour of dartsass-rails, and which the Sidekiq worker has no
business loading.

## Updating

Bump the version in `package.json`, `yarn install`, then replace the directories:

    rm -rf vendor/sass/bootstrap/scss vendor/sass/@fortawesome
    cp -R node_modules/bootstrap/scss vendor/sass/bootstrap/scss
    mkdir -p vendor/sass/@fortawesome/fontawesome-free
    cp -R node_modules/@fortawesome/fontawesome-free/scss \
          vendor/sass/@fortawesome/fontawesome-free/scss

Font Awesome's webfonts live in `public/webfonts` and are served from there directly; if
the Font Awesome version changes, copy those across too:

    cp node_modules/@fortawesome/fontawesome-free/webfonts/fa-{solid-900,regular-400,brands-400,v4compatibility}.* \
       public/webfonts/

Then `bin/rails dartsass:build` and check the diff in `app/assets/builds/application.css`.
