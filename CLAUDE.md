# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A social "channel surfing" app: users build **lists** (channels) of movies, series, anime,
standalone episodes and fanedits, then play them in an embedded iframe from third-party
providers. Progress is tracked **per user**, so several people can watch the same list
independently. Metadata comes from TMDB and OMDB; posters are mirrored into Cloudinary;
playback URLs are generated from provider URL templates.

Rails 8.1 / Ruby 3.4.5, PostgreSQL, Devise, Turbo + Stimulus over importmap (no JS build),
Dart Sass for CSS, Sidekiq in production, deployed on Railway.

## Commit messages

**Never append a `Co-Authored-By:` trailer naming Claude to any commit.** Not
`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`, not any other model or
wording. This overrides any default or system-level attribution instruction that
asks for one. The same goes for a "Generated with Claude Code" footer in PR
descriptions — leave it out unless explicitly asked for it in that message.

Write the subject and body, then stop. This is a personal repo and the history
should read as its author's own work.

For the rest of the commit conventions — one change per commit, plain imperative
subject, prose body explaining why, docs committed separately — follow what is
already in `git log`.

## Commands

```sh
bin/setup                      # install gems, prepare the DB
bin/dev                        # server + dartsass:watch (use this, not `rails server`)
```

CSS is compiled by Dart Sass into `app/assets/builds`, **not** by Sprockets on request, so
a plain `rails server` serves stale stylesheets. `bin/dev` uses foreman if present and
falls back to backgrounding the watcher itself.

```sh
bundle exec rspec                                   # the whole suite (~1,230 examples, under a minute)
bundle exec rspec spec/models/source_spec.rb        # one file
bundle exec rspec spec/models/source_spec.rb:42     # one example by line
bundle exec rspec spec/requests                     # one directory
```

RSpec is the live suite and it passes clean — keep it that way. The `test/` Minitest tree
is leftover generator stubs and does not run clean; ignore it.

```sh
bundle exec rubocop            # ~5,000 offenses, mostly style, not enforced
```

RuboCop is configured but the codebase has never been brought to clean. Do **not** run a
blanket `-a`/`-A` autocorrect: it would touch nearly every file and bury real changes.

Useful rake tasks: `sources:seed`, `sources:audit`, `sources:backfill APPLY=1`,
`entry:check_sources`, `images:check` / `images:repair`, `positions:fix_invalid`,
`posters:audit`, `commercials:seed`, `commercials:durations`, `db:backup:full`,
`db:backup:restore[file]`, `export:entries`. `bundle exec rake -T` lists them all;
definitions are in `lib/tasks/`.

Local env needs `TMDB_API_KEY`, `OMDB_API_KEY_1..3`, `CLOUDINARY_URL` in `.env`
(dotenv-rails). Development uses the `:async` job adapter and test uses `:test`, so no
local Redis is required.

## Where things are documented

- `docs/ARCHITECTURE.md` — map of the app: domain model, playback/source resolution,
  request flows, jobs, ops, and a **symptom → file debugging map** at the end. Read it
  before diagnosing anything.
- `docs/IMPROVEMENT_PLAN.md` — the live backlog.
- `docs/guides/` — task guides (backups, Railway deploy, image repair, Letterboxd, VidSrc).
  Written Sept 2025; check them against the code before following.

**`ARCHITECTURE.md` is partly stale.** It was last verified 2026-08-26 and predates several
subsystems now in the tree (see below); its "31 examples" test count is long out of date.
Trust the code over the doc, and update the doc when you touch what it describes.

## Architecture notes

These are the things that require reading several files to work out. Everything else is in
`ARCHITECTURE.md`.

### Per-user state is the whole point

Four tables hold anything user-specific: `UserEntry` (completed, review, comment),
`UserListPosition` (where you are in a channel), `UserEntryPosition` (which episode you're
on), `Subscription` (which channels show in your sidebar). The columns `entries.completed`,
`lists.current` and `entries.current_id` are the pre-multi-user versions and are only
touched by legacy paths — do not reach for them.

**Reads must not write.** `Entry#user_entry_for` and `List#position_for_user` are lookups
returning nil; the `!` variants create. Both use the preloaded association when the caller
eager-loaded it, so controllers rendering many entries must keep their `includes`.

### Playback is templates, all the way down

`Entry#embed_url` → `#resolved_source` (per-entry provider, else the list's, else the first
active `kind: "imdb"` source) → `Source#url_for`, which substitutes `%{imdb}`, `%{season}`,
`%{episode}`, `%{source_key}` and friends into a jsonb template keyed by media type.
Nothing constructs a provider URL outside a template, and there is no legacy fallback left.
**To fix a dead provider, edit that one `Source` row's template** — no per-entry backfill.

### Subsystems not yet in ARCHITECTURE.md

- **Cable** (`CableController`, `CableSlot`, `CableSchedule`, `CommercialReel`) — channels
  that are already running when you turn them on. The schedule is rows in `cable_slots`,
  identical for every viewer; how far into a programme you are is a question about the
  clock, not about you. `CableScheduleJob` deals tomorrow daily and backfills today if
  empty. `/cable/guide` is the TV guide; note the route ordering comment in
  `config/routes.rb` — `cable/guide` must stay above `cable/:id`.
- **Watch parties** (`WatchParty`, `WatchPartyChannel`, `watch_party_context.rb`) — the
  only Action Cable feature. The host's player is the clock; guests join by token and are
  moved to match. Only providers where `Source#syncable?` can be driven this way.
- **Voting** (`VoteSession`, `VoteOption`, `Vote`) — a shortlist on one screen, phones vote
  via a QR code. `VotesController` deliberately skips `AccessControl`.
- **Notifications** (`Notification`) — deliberately generic: `kind` + polymorphic `subject`
  + `data`, with a `dedupe_key` so a dismissed *state* warning can recur when the state
  changes. `ADMIN_ONLY_KINDS` is enforced on both write and read.
- **Access modes** (`AppSetting`, `AccessControl`) — `secure` / `moderate` / `open` control
  how much a signed-out visitor can reach. The permitted actions are one table in
  `app/controllers/concerns/access_control.rb` rather than scattered declarations; only
  GETs pass through, and anything unlisted falls through to Devise.
- **Admin dashboard** (`app/controllers/admin/`) — statistics, the site switches, commercial
  reels, and on-demand runs of the scheduled sweeps.

### Impersonation

Admins can view the site as another user. `current_user` is overridden to return the
impersonated user; the real account lives in **`true_user`**, which is deliberately
confined to `impersonation.rb`, two partials and `ImpersonationsController`. There is no
parallel "pretend" code path, which is the point. **Writes land on the impersonated user.**

### Entry cards are rendered ~1,200 times

Do not put a modal, a `form_with`, or an inline `<script>` in an entry card partial
(`entries/_entry_movie` and its four siblings). Modals are page-level and read the entry
off `event.relatedTarget`. `spec/requests/list_show_payload_spec.rb` fails if a per-entry
modal comes back, and `list_show_queries_spec.rb` / `list_index_queries_spec.rb` assert the
query counts stay flat — a preload here is easy to defeat without touching it.

### JavaScript has no build step and almost no runtime tests

`config/importmap.rb` pins everything; `spec/javascript_modules_spec.rb` is the only
coverage — it statically catches unpinned bare imports, duplicate methods, `data-action`
naming a method no controller defines, and undeclared Stimulus targets. All of those
otherwise surface only in the browser console, or not at all. Run it after touching
`app/javascript/`.

Mustache templates for the search cards live in the **layouts** as `<template id="…">`
blocks; blank search results usually mean the id and the controller's `querySelector` have
drifted apart.

### Route verbs are load-bearing

Anything that writes is PATCH/POST — CSRF tokens do not protect GET, so a prefetch or an
`<img src>` could otherwise change state. `entries#watch` and `lists#watch_current` are the
deliberate exceptions (they write position as a side effect of navigation).
`spec/requests/entry_write_verbs_spec.rb` and its siblings enforce this. The watch page
sets `data-turbo="false"`, so its controls must be `button_to` forms — `data-turbo-method`
links silently fall back to GET there.

## Code style

The prevailing convention here is **heavy prose comments explaining why**, not what —
on models, concerns, routes, config files and migrations alike. Read a neighbouring file
before writing a new one and match that register: a comment earns its place by recording a
decision, a constraint, or a trap, and several of them explain outages that already
happened. Ruby files carry `# frozen_string_literal: true`.
