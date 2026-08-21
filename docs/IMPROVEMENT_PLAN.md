# How To Watch — Improvement Plan

**Written:** 2026-08-21, against `master` @ `a777d88` + uncommitted working tree.
**Companion:** [ARCHITECTURE.md](ARCHITECTURE.md) — read that first for how anything works.
**Supersedes:** `REFACTORING_TODO.md` (Oct 2025). Several of its items are now done
(indexes on `user_entries`/`subscriptions`, per-user positions, the `Source` provider
system); the rest are folded in below. Delete it once you're happy with this file.

Everything below was verified by reading the code — no speculative items. Line numbers are
from the working tree at the time of writing.

**Status legend:** ✅ done · ⬜ open. Items marked ✅ were fixed on 2026-08-21; the fix is
described inline so the history stays readable.

---

## P0 — Correctness and security

### 1. ✅ CSRF protection is disabled for every entry write
`app/controllers/entries_controller.rb:9` — `skip_before_action :verify_authenticity_token`
applies to the whole controller: `create`, `update`, `destroy`, `set_source`,
`update_poster`, `complete`, `review`. Any page on the internet can delete entries from a
logged-in user's lists.

**Fix:** delete the line and re-run the flows that motivated it (the JSON `fetch` calls in
`search_controller.js` / `mobile_search_controller.js` / `poster_selector_controller.js`).
Turbo sends the token automatically; raw `fetch` needs
`headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }`.
If one specific JSON endpoint truly must stay open, scope the skip to that action only.

**Done:** the skip is gone. Every JS write-path (`search`, `list_search`, `mobile_search`,
`poster_selector`, `sort`) already sent `X-CSRF-Token`, so nothing needed changing there.

### 2. ✅ A TMDB API key is hardcoded in ten places
`search_controller.js:12`, `list_search_controller.js:16`, `mobile_search_controller.js:17`,
`episodes_controller.js:18`, `lists/show_mobile.html.erb:1`, `lists/index_mobile.html.erb:6`,
`shared/_navbar.html.erb:14`, plus server-side `|| '7e1c…'` fallbacks in
`entries_controller.rb:723`, `lists_controller.rb:252`, `pages_controller.rb:39`,
`omdb_api.rb:83`.

Browser-side TMDB keys are always public, so this isn't a leak you can undo — but the
server fallbacks mean production silently keeps working on a personal key when
`TMDB_API_KEY` is unset, and the key is now in git history.

**Fix:** rotate the key; expose it once (`content_tag :meta, name: "tmdb-key", content: ENV["TMDB_API_KEY"]`
in the layout, or a single Stimulus value on `body`) and read it from there in JS; delete
every `|| '7e1c…'` fallback so a missing env var fails loudly.

**Done (code side):** all three layouts emit `<meta name="tmdb-key">`; the four Stimulus
controllers read it; server code goes through `TmdbService.api_key`, which is
`ENV.fetch` so a missing key raises instead of falling back. The literal no longer appears
anywhere in `app/`. **Still yours to do: rotate the key at themoviedb.org** — it is in git
history and cannot be un-published.

### 3. ⬜ Reading completion state writes to the database
`Entry#user_entry_for` (`app/models/entry.rb:272`) is `find_or_create_by`, and
`Entry#completed_by?` (`:277`) calls it. `entries/_completion_status.html.erb` renders per
entry, so **viewing a list INSERTs a `user_entries` row for every entry on the page**.
Same pattern in `List#position_for_user` (`app/models/list.rb:185`), called by
`current_entry` on every list card.

Consequences: writes on GET, junk rows for entries a user never touched, and `user_entries`
rows that make `find_next_incomplete_entry_for_user`'s left-join logic do more work.

**Fix:** split read from write — `user_entry_for` → `user_entries.find_by(user:)` for reads,
a separate `user_entry_for!` (or `find_or_create_by`) on the write paths
(`mark_completed_by!`, `review`, position updates). `completed_by?` becomes
`user_entries.find_by(user: user)&.completed?` — and with a preload, free.

### 4. ✅ Visiting a list wipes its saved grouping
`app/controllers/lists_controller.rb:609` — `@list.update(settings: params[:criteria], sort: params[:sort])`
runs on every `show` for the owner. A plain visit has no params, so `settings` and `sort`
are set to `nil` and the remembered view is lost.

**Fix:** only write when the params are present:
`@list.update(settings: params[:criteria], sort: params[:sort]) if params[:criteria].present? || params[:sort].present?`

**Done:** the write is now guarded, and `load_entries` *reads* `@list.settings` as the
default grouping — the column was previously written but never used, so the remembered
view never actually came back. Covered by `spec/requests/lists_spec.rb`.

### 5. ✅ Grouping crashes on incomplete entries
`ListsController#filter_entries:612` — `Genre` does `entry.genre.split(',')` and `Year` does
`entry.year >= year`. Both are nullable columns (any hand-added/fanedit entry), so the list
page 500s. **Fix:** `entry.genre.to_s.split(',')`, and `.select { |e| e.year.present? && … }`
with an "Unknown" bucket.

**Done:** Genre/Year/Watched are all nil-tolerant now (blank genres land in "Other"), and
section keys are sorted by a helper that handles the string/number mix — grouping by
Rating or Length with any nil value used to raise `ArgumentError` in the view, which
re-sorted the keys itself instead of using the controller's `@sections`. See also #24.

### 6. ✅ Letterboxd sync raises for lists you don't own
`app/controllers/letterboxd_controller.rb:133` — `entry.list.public?`. `List` has no
`public?` method (the column is `private`), so this is a `NoMethodError` for any entry
whose list belongs to someone else. **Fix:** `!entry.list.private?`.

**Done.**

### 7. ✅ `lists#top_entries` references an undefined variable
`app/controllers/lists_controller.rb:235` — `scraper_results[:title]` is never assigned;
the action raises `NameError` whenever a created entry has no `series`.
**Fix:** the scraper already returns per-episode `:title`; either use the episode hash or
drop the line.

**Done:** now uses `episode[:title]` from the scraper result; the stray `puts` next to it
became `Rails.logger.info`.

### 8. ✅ Deleting an entry via HTML redirects to a route that doesn't exist
`app/controllers/entries_controller.rb:186` — `redirect_to entries_path`. There is no
`GET /entries`. **Fix:** redirect to `list_path(@list)`.

**Done.** Covered by the existing controller spec, which had been failing.

### 9. ✅ A rescue mislabels every series-import failure
`entries_controller.rb` `create` wraps `OmdbApi.get_series_episodes(@entry)` in a bare
`rescue` that flashes "This already exists in your list". The common real cause is
`main_entry.season.times` when `season` is `nil` (OMDB returned no `totalSeasons`).
**Fix:** guard `season` in `OmdbApi.get_series_episodes`, rescue narrowly, and surface the
real message.

**Done:** `get_series_episodes` returns early (with a log line) when there is no season
count, and the controller now reports the actual exception message.

### 10. 🟡 Both test suites are broken, and linting can't run
- RSpec: **15 of 20 examples fail** — every controller spec dies on
  `Could not find a valid mapping for #<User…>` (`spec/support/devise.rb` /
  `ControllerMacros` not wiring `@request.env["devise.mapping"]`). Only the 5 `Entry`
  model specs pass.
- Minitest: **7 runs, 7 errors** — `test/controllers/entries_controller_test.rb` calls a
  nonexistent `entries` fixture accessor. The `test/` tree is otherwise empty generator stubs.
- RuboCop: **won't start** — `.rubocop.yml` requires `rubocop-rspec`, which isn't in the Gemfile.

**Fix, in order:** pick one framework (RSpec — it has the only real tests), delete the other
tree, repair the Devise mapping in `spec/support/`, add `rubocop-rspec` (or drop the
`require`), then add specs for the flows that keep breaking: `Entry#embed_url` /
`Source#url_for` across all five media types, completion + position advance, and
`filter_entries`.

**Mostly done — RSpec is green at 27 examples, 0 failures, and RuboCop runs.**
- Root cause of the Devise failures was **Rails 8 lazy route loading**: `Devise.mappings`
  is empty until the routes are drawn, so `Devise.mappings[:user]` was `nil` in every
  controller spec. `spec/rails_helper.rb` now calls `Rails.application.reload_routes_unless_loaded`,
  loads all of `spec/support/`, uses the plural `fixture_paths`, and includes
  `Devise::Test::IntegrationHelpers` for request specs.
- Test env now uses the `:test` job adapter (entry callbacks enqueue network jobs).
- The user factory generates unique emails.
- Stale specs asserting pre-multi-user behavior were rewritten against current behavior
  (create answers with turbo streams; completion lives in `UserEntry`).
- `rubocop-rspec` added to the Gemfile; `.rubocop.yml` had obsolete `RSpec/FilePath`,
  `RSpec/Rails/*`, `RSpec/FactoryBot/*` and `Capybara/*` entries (those cops moved to
  separate gems) — removed, and `TargetRubyVersion` corrected to 3.4.
- **Still open:** the `test/` Minitest tree (7 stub tests, all erroring) should be deleted
  now that RSpec is the live suite — left in place pending your call.

### 11. ✅ No queue backend in production
Active Job falls back to the in-process `:async` adapter (`config/environments/production.rb:62`
is still the commented-out `:resque` line). Poster attachment and source checks are silently
dropped on every deploy. Redis is already provisioned for Action Cable.
**Fix:** add Sidekiq (or `solid_queue`) and a worker process in the `Procfile`.

**Done (2026-08-21):** Sidekiq 7.3 on the Railway Redis service, running as a separate
`worker` service with its start command in its Railway service settings — separate because the
web start command runs `assets:precompile && db:migrate`, and two services racing
migrations is a hazard. `ApplicationJob` gained `discard_on ActiveJob::DeserializationError`
(jobs now outlive the process that enqueued them) and `retry_on ActiveRecord::Deadlocked`.
`/sidekiq` is mounted for admins. Development stays on `:async`, so no local Redis is
needed. Covered by `spec/jobs/entry_jobs_spec.rb`.

### 24. ✅ `?criteria=` called any method it liked on every entry (found 2026-08-21)
`ListsController#filter_entries`'s default branch was
`@list_entries.group_by { |entry| entry.send(criteria.downcase) }`, with `criteria` coming
straight from the query string. `GET /lists/:id?criteria=destroy` **deleted every entry in
the list** — verified: the regression spec, run against the old code, shows `Entry.count`
going from 1 to 0. Any zero-argument method was reachable this way.

**Done:** `GROUPING_CRITERIA` whitelists the eight groupings the UI actually offers,
anything else falls back to `Position`, and the lookup uses `public_send`. Covered by
`spec/requests/lists_spec.rb`.

### 25. ✅ Editing an entry with no source URL raised NoMethodError (found 2026-08-21)
`EntriesController#fix_external_sources` did `url.include?("mega")` on a nil `source`.
Every entry created from TMDB/OMDB has no hand-entered source, so saving the edit form for
one 500'd. Surfaced by the controller specs once they could run at all.

**Done:** returns early on a blank URL. `@entry.media.empty?` in the custom-entry branch
had the same nil problem and is now `.blank?`.

### 26. ⬜ State-changing actions are routed as GET
`complete`, `reportlink`, `duplicate`, `repair_image`, `migrate_poster`,
`increment_current`, `decrement_current` and `shuffle_current` are all `get` routes that
write to the database. CSRF tokens do not protect GET, so #1's fix does not cover these:
any `<img src>` or link prefetch can still toggle your watched state. Browser prefetchers
and crawlers can trip them by accident, too.

**Fix:** move them to `patch`/`post` and update the callers — `completed_controller.js` and
`link_controller.js` `fetch` them directly, and `watch.html.erb` uses `link_to` for the
navigation arrows (they would become `button_to`, which needs the surrounding CSS checked).
Medium-sized change across routes, two Stimulus controllers and the player UI, so it was
left out of the P0 batch rather than done halfway.

### 27. ✅ Railway config-as-code is removed on 2026-12-01 (deadline)
`railway.json` supplies the web service's start command
(`rails assets:precompile && rails db:migrate && rails server`). Railway deprecated
config-as-code: existing files are read until **2026-12-01**, and from **2026-08-28**
services that never used it cannot opt in. On the cutoff the file is simply ignored, so the
start command silently reverts to the dashboard setting or the Procfile — losing
`assets:precompile` and `db:migrate` if neither supplies them. Nothing breaks loudly; the
next deploy just ships unmigrated.

**Fix:** migrate to Infrastructure as Code — a `.railway/railway.ts` describing the project
(web, worker, Postgres, Redis), with `railway config migrate --apply --delete-files`, then
`railway config plan` / `railway config apply`. Needs a Railway CLI newer than 4.7.3.
Do it deliberately: `apply` acts on the whole project, so read the plan output first.
Interim safety net: confirm the web service's dashboard start command (or the Procfile
`web:` line) matches `railway.json`, so the cutoff is a no-op.

**Done (2026-08-21), the simple way instead:** `railway.json` is deleted. It was only
supplying the web start command, and a repo-root config file applies to *every* service
built from the repo while outranking the dashboard field — which is what stopped the
`worker` service from overriding it. Start commands now live in each service's Railway
settings, mirrored by the `Procfile` (which Railway's builder honours as the fallback).
No config-as-code left, so the December cutoff is a no-op and the IaC migration becomes
optional rather than a deadline.

### 28. ⬜ `sassc-rails` drags a native `ffi` dependency into every process
`sassc-rails` is deprecated *and* it is the reason the Sidekiq worker loads `ffi` at all:
`Bundler.require` pulls in `sassc-rails → sassc → ffi`, which needs `libffi.so.8` at
runtime. That crashed the worker's first deployment on Railpack, whose runtime image is
minimal. Worked around with `RAILPACK_DEPLOY_APT_PACKAGES=libffi8 libpq5`, but the worker
has no business loading an SCSS compiler.

**Fix:** move to `dartsass-rails` (no FFI, actively maintained). That removes the native
dependency from every process, not just the worker, and clears the deprecated gem out of
the Gemfile. Check `app/assets/stylesheets` compiles identically — the SCSS here is plain
nesting/variables plus Bootstrap, so it should port cleanly.

---

## P1 — Performance

### 12. N+1 queries on the two hottest pages
- `lists/index.html.erb:8,57,100` — `list.current_entry(current_user)` per card. For
  unordered lists that's `find_random_incomplete_entry_for_user`, which loads **all**
  incomplete entries and calls `.sample` in Ruby; for ordered lists it's a
  `find_or_create_by` on `user_list_positions`.
- `shared/_sidebar.html.erb:88` → `ApplicationHelper#find_now_playing_for_sidebar` runs
  4–6 queries **on every page render**, including one that joins `lists → entries`.
- `entries/_completion_status` → `completed_by?` per entry (see #3).

**Fix:** preload `user_list_positions` and `user_entries` for the current user in the
controller and pass them down; replace `.sample` with `ORDER BY RANDOM() LIMIT 1`; cache
the "now playing" lookup per request (`@now_playing_entry ||=` is already half-wired).

### 13. Missing indexes
`entries` has an index on `list_id` only. Add:
`entries (list_id, position)`, `entries (imdb)`, `entries (media)`,
`subentries (entry_id, season, episode)`, `lists (user_id, private)`.
(The `user_entries` / `subscriptions` / `user_*_positions` indexes from the old TODO are
already in `schema.rb`.)

### 14. Synchronous third-party HTTP inside requests
- `entries#watch` — a TMDB episode fetch on every play.
- `lists#add_season` — one TMDB call per episode plus one per previous season for anime;
  a 24-episode season is ~25 sequential round trips in a web request.
- `pages#watch_now` — up to three TMDB calls before first paint.
- `letterboxd#bulk_sync` — loops all completed entries **with `sleep(0.5)`** in-request.

**Fix:** move `add_season` and `bulk_sync` into jobs (after #11) with a Turbo-stream or
poll for completion; cache TMDB episode/show lookups (`Rails.cache.fetch`, they never
change); make the watch-page episode details lazy (`turbo_frame` with `loading: :lazy`).

### 15. Row-by-row position rewrites
`List#normalize_entry_positions!` issues one `UPDATE` per entry and is called inside
`entries#update_position`'s transaction, on top of `shift_positions`' two bulk updates.
**Fix:** one `upsert_all`/`update_all` with a computed `row_number()`, or keep positions
sparse (gaps of 100) so reorders rarely renumber.

### 16. Housekeeping
`log/` is **151 MB** and `tmp/` 50 MB locally; `public/assets` 46 MB is committed build
output. Add log rotation, and confirm `public/assets` is gitignored (it is) but purge
what's on disk.

---

## P2 — Structural refactors

### 17. Fat controllers
`EntriesController` is 911 lines, `ListsController` 682. The heavy blocks are all import
logic that has nothing to do with HTTP:
- `entries#handle_episode_from_tmdb` (~120 lines) → `EpisodeImporter`
- `lists#add_season` (~140 lines) → `SeasonImporter`
- `entries#fetch_posters` (~110 lines of TMDB/OMDB juggling) → `PosterCandidates`
- `lists#add_to_list` / `#add_to_favorites` are the same method twice → one service +
  two thin actions.

Extracting these also makes them testable and reusable from the jobs in #14.

### 18. Three near-identical TMDB search controllers
`search_controller.js` (272), `list_search_controller.js` (524), `mobile_search_controller.js`
(446) — 1,242 lines that all wrap the same `TmdbService`/`TmdbMapper` and differ mainly in
which Mustache template id they query and where they POST. The matching `<template>` blocks
are duplicated between `layouts/application.html.erb` and `layouts/mobile.html.erb`.
**Fix:** one `tmdb_search_controller` with values for `templateId`, `submitUrl`, and mode;
move templates into a shared partial rendered by both layouts.

### 19. Mobile as a parallel universe
User-agent sniffing (duplicated in both controllers) selects `*_mobile` views and a
476-line `layouts/mobile.html.erb`. Every feature has to be built twice, and it already
drifts (mobile has favorites, desktop doesn't).
**Fix (incremental):** move the sniffing into `ApplicationController` as one helper; then
collapse the layouts by making the desktop views responsive, starting with
`lists/index_mobile` (which is mostly the same cards).

### 20. Two eras of playback code coexist
The `Source` template system is live, but URL strings are still built by hand in
`Entry.generate_source`/`generate_source_two`, `Subentry.generate_source`/`fix_source_url!`,
`OmdbApi.fetch_episodes_from_tmdb`, `lists#add_season`, and `entries#handle_episode_from_tmdb`
— eight places that hardcode `vidsrc.cc` / `v2.vidsrc.me`, the exact coupling the `Source`
refactor was meant to remove. New entries still get `source`/`source_two` written.

**Plan:** (a) stop *writing* legacy columns on create — importers set `provider`/`source_key`
only; (b) keep `legacy_embed_url` as a read-time fallback for existing rows; (c) once
production entries all resolve through a `Source` (a one-off query can confirm), drop
`entries.source`, `source_two`, `preferred_source`, `lists.preferred_source`,
`subentries.source`, and the `preferred_source` inclusion validations.

### 21. `season`/`episode` stored as strings on `subentries`
Forces `CAST(NULLIF(season, '') AS INTEGER)` in `UserEntryPosition` (×3), `Entry#set_current`,
`OmdbApi`, and `Subentry#calculate_absolute_episode_number`. **Fix:** a migration casting
both to integer, then delete the casts.

### 22. Position bookkeeping has three implementations
`Entry.next_position` (max + 1), `@list.entries.count + 1` (still in `lists#add_season`;
collides after a delete — one instance was just fixed in `entries_controller.rb:783` in the
working tree), and `List#next_position_for_parent`. **Fix:** one `List#next_position` used
everywhere, covering entries and child lists.

### 23. `auto_next` is a setting that does nothing
Present in the schema, both list forms, and `watch.html.erb`'s `data-list-auto-next`, but
the only consumer — `auto_advance_controller.js` — has its countdown commented out
("Disabled for debugging"). Either finish it (on player end / on complete, follow the
existing `increment_current` vs `shuffle_current` branch) or remove the setting and the UI.

---

## P3 — Dead code and cleanup

Safe to delete (verified: zero references outside their own definition):

| Item | Location |
|---|---|
| `mark_previous_incomplete` (no route) | `entries_controller.rb:293` |
| `find_now_playing_entry` (duplicate of the helper) | `lists_controller.rb:645` |
| `Entry#attach_poster_immediately` (unused since posters went async) | `entry.rb:392` |
| `Entry#complete(boolean)`, `Entry#fix_subentry_sources!` | `entry.rb:265,245` |
| `Entry#set_current` (only caller is the dead action above) | `entry.rb:207` |
| `ListUserEntry` + `Follow` models and their tables | superseded by `Subscription` / `UserListPosition` |
| `LetterboxdSyncJob` (nothing enqueues it; verified 2026-08-21) | `app/jobs/letterboxd_sync_job.rb` |
| `hello_controller.js`, `cinema`, `frame_loader`, `omdb` controllers | no `data-controller` reference |
| `app/javascript/test.js` (`let idk = 23`) | |
| `pages#test` + `views/pages/test.html.erb`, `pages/home.html.erb` (scaffold placeholder that is the only public page) | routes + views |
| `components/_test.scss` | |
| `clear_and_import.rb` (root; destroys all data, reads `/tmp/tables.json`) | move to `lib/tasks/` or delete |
| `pid` file, `path/` directory, `.DS_Store` | committed junk |
| `List::OFFSET`'s commented `random:` key; `Errors::NoResults` concern | |

**Also:**
- **Docs sprawl:** nine root-level `*_GUIDE.md` files from Sept 2025 plus a stale
  `REFACTORING_TODO.md`. Move the still-useful ones into `docs/`, delete the rest, and let
  `docs/ARCHITECTURE.md` be the entry point (README should link to it).
- **`puts` in production code:** `Entry.create_from_source`, `TmdbService`, `ImdbScraper`,
  `OmdbApi` — should be `Rails.logger`.
- **Migrations:** the `20250110000001..7` "update vidsrc sources" / "fix episode sources"
  data migrations are historical no-ops now; leave them (they've run) but don't add more
  data-fixes as migrations — use rake tasks so they're re-runnable.
- **Gemfile:** `simple_form` is pinned to a **git branch** (unreproducible builds — pin a
  version), `webdrivers` is abandoned (Selenium 4 manages drivers itself), `sassc-rails` is
  deprecated (`dartsass-rails` when you next touch CSS). `redis` is only used by Action Cable.
- **Empty CSP initializer** — with third-party iframes everywhere a real policy is work, but
  at minimum set `frame_src` and `img_src` deliberately rather than leaving it unset.

---

## Suggested order of work

1. ~~**Session 1 — stop the bleeding:** #1, #2, #4, #5, #6, #7, #8, #9, plus #24 and #25
   found along the way.~~ **Done 2026-08-21.**
2. ~~**Session 2a — make failures visible:** #10, the RSpec suite and RuboCop.~~ **Done**
   (27 examples green; `test/` tree still to be deleted).
3. **Next up — #26** (state-changing GETs): the other half of the CSRF story, and the
   natural follow-on from #1.
4. ~~**Then #11** (real queue backend) so #14 has somewhere to go.~~ **Done 2026-08-21.**
5. **Then #3 + #12 + #13** together — the read/write split, the N+1s and the indexes are
   what make the list and sidebar pages fast.
6. **Then P3** — the dead-code sweep. Cheap, and it shrinks the surface for everything after.
7. **Then, one at a time:** #17 (extract importers) → #14 (move them to jobs) → #20 (retire
   the legacy source columns) → #21 → #18/#19 (front-end consolidation).
