# How To Watch — Architecture & Operations Reference

**Purpose:** the map of this codebase. Read this before diagnosing anything; the last
section ("Debugging map") goes from symptom → the file that actually owns the behavior.

**Last verified:** 2026-08-25 against `master` @ `2caaa3b`.

---

## 1. What the app is

A personal/social "channel surfing" app. Users build **lists** (channels) of movies,
series, anime, standalone episodes and fanedits, then play them in an embedded iframe
from third-party streaming providers. Progress (what you've watched, where you are in a
list, which episode you're on) is tracked **per user**, so several users can watch the
same list independently.

Metadata comes from TMDB and OMDB; posters are mirrored into Cloudinary; playback URLs
are generated from provider URL templates.

---

## 2. Stack

| Layer | Choice |
|---|---|
| Ruby / Rails | 3.4.5 / Rails 8.1.3.1 (`config.load_defaults` still **8.0** — bumping defaults is a separate, behaviour-changing step; run `bin/rails app:update` to generate `new_framework_defaults_8_1.rb` and work through it) |
| DB | PostgreSQL (`pg_search` for entry search) |
| Auth | Devise (`database_authenticatable, registerable, recoverable, rememberable, validatable`) |
| Views | ERB + Turbo + Stimulus, Bootstrap 5 via importmap, Mustache.js for client-rendered search cards |
| Assets | Sprockets + **`dartsass-rails`** for CSS (compiled to `app/assets/builds`, then digested by Sprockets, with `autoprefixer-rails` as a postprocessor), **importmap-rails** for JS |
| Files | Active Storage → **Cloudinary** (`config.active_storage.service = :cloudinary` in *both* dev and prod) |
| Jobs | Active Job → **Sidekiq** in production (Redis-backed); `:async` in development, `:test` in test (see §8) |
| Redis | Railway `Redis` service on the private network; used by Sidekiq and available to Action Cable |
| Hosting | Railway: `how-to-watch` (web) + `worker` (Sidekiq), plus `Postgres` and `Redis` |

---

## 3. Domain model

### 3.1 Core content

**`User`** — Devise account. Flags: `admin` (can edit anything, manage `Source`s, set
default lists), `dark_mode`. Letterboxd OAuth tokens live here. On create it
auto-subscribes to default lists and **creates a "<Name>'s Favorites" list** with
`mobile: true, private: true` (`app/models/user.rb:186`).

**`List`** — a channel. Owned by a user.
- `ordered` — true: play in `position` order; false: play a random unwatched entry.
- `private`, `default` (admin-set; everyone auto-subscribes), `mobile` (marks the user's
  favorites list used by the mobile UI), `reviewable` (prompt for a rating after finishing).
- `auto_play` (flows into the embed URL's autoplay param) and `auto_next`
  (**declared in forms and the DB but no advance logic is implemented**).
- `settings` / `sort` — remembered grouping criteria for the show page (`settings` is read
  back as the default grouping; only an explicit `?criteria=`/`?sort=` overwrites them).
- `provider_id` → `Source`: the list's default streaming provider.
- Legacy: `current` (int, list-level "current position" from before per-user tracking),
  `preferred_source` (int 1/2), `parent_list_id`.

**Nesting.** Lists can contain lists. The live mechanism is `ListRelationship`
(`parent_list_id`, `child_list_id`, `position`), many-to-many, with cycle checks in
`List#can_be_added_to?` / `#is_descendant_of?`. `lists.parent_list_id` is the superseded
single-parent version, still declared as a `belongs_to`.

**`Entry`** — one watchable item in a list. `media` is free text, normalized to lowercase,
and drives nearly every branch in the app: `movie`, `series`, `anime`, `episode`, `fanedit`.
- Identity: `imdb`, `tmdb`, `series_imdb` (for episodes/series).
- Art: `pic` (remote URL) plus an Active Storage `poster` attachment (Cloudinary).
- Ordering: `position` (integer, within the list).
- Playback: `provider_id` → `Source`, `source_key` (opaque id for "direct" providers).
- `current_id` → `Subentry`: legacy list-level "current episode" pointer.

**`Subentry`** — an episode belonging to a series/anime `Entry`. `season` and `episode` are
integers (they were strings until 2026-08-25, which is why old code sorted with
`CAST(NULLIF(...))`). Anime can use an *absolute* episode number via
`Subentry#calculate_absolute_episode_number`, computed only when a template asks for
`%{absolute_episode}`.

**`Source`** (`app/models/source.rb`) — a streaming provider definition. Owns URL
**templates** (jsonb, keyed by media type + `"default"`) with `%{imdb}`,
`%{series_imdb}`, `%{season}`, `%{episode}`, `%{absolute_episode}`, `%{source_key}`
placeholders. `kind` is `imdb` (works for any entry with an IMDb id) or `direct` (needs
the entry's own `source_key`: a Drive file id, mega key, YouTube id, or a full URL).
`autoplay_param` is appended when autoplay is on. Substitution is a plain `gsub`, no eval.

### 3.2 Per-user tracking (the important part)

| Model | Grain | Holds |
|---|---|---|
| `UserEntry` | user × entry | `completed`, `completed_at`, `last_watched_at`, `review` (1–10), `comment` |
| `UserListPosition` | user × list | `current_position` (an `entries.position` value) |
| `UserEntryPosition` | user × entry | `current_subentry_id` — which episode you're on |
| `Subscription` | user × list | which channels appear in your sidebar |

**Reads must not write.** `Entry#user_entry_for` / `List#position_for_user` are lookups
returning nil; the `!` variants (`user_entry_for!`, `position_for_user!`) create. Both reads
use the preloaded association when the caller eager-loaded it, so controllers that render
many entries should `includes(:user_entries)` / `includes(:user_list_positions)`.

Rule of thumb: **anything user-specific is in one of these four tables.** The columns
`entries.completed`, `lists.current`, and `entries.current_id` are the pre-multi-user
versions and are only touched by legacy paths.

### 3.3 Dead / legacy tables still in the schema

`follows`, `list_user_entries` (superseded by `subscriptions` + `user_list_positions`),
`failed_entries` (write-only error log from CSV/OMDB imports).

---

## 4. Playback: how an embed URL is produced

This is the piece most likely to break, since providers die regularly.

```
Entry#embed_url(subentry:, autoplay:)
  └─ Entry#resolved_source                     app/models/entry.rb
       ├─ entry.provider           (per-entry override)
       ├─ else list.provider       (channel default)
       ├─ if that source is missing/inactive and entry.imdb exists:
       │     first active kind:"imdb" Source by position
       └─ Source#url_for → #build_url → template_for(media) → %{token} substitution
  └─ blank result means nothing can play it; entries#watch redirects with a notice
```

- **Series/anime** pass the user's current `Subentry` so `%{season}/%{episode}` resolve.
- **`entries#set_source`** (the buttons under the player) writes `entry.provider` after
  checking `Entry#eligible_sources`.
- **`pages#watch_now`** has no `Entry` at all — it builds URLs straight from
  `Source#build_url` with a hand-built vars hash, and the switcher swaps `iframe.src`
  client-side (`app/views/pages/_watch_now_source_switcher.html.erb`).
- Seed the providers with `rails sources:seed` (`db/seeds/sources.rb`, create-only so admin
  edits survive). One-time migration from the old columns: `rails sources:backfill APPLY=1`.

**To fix a dead provider: edit that one `Source` row's template** (admin pencil icon under
the player, or `rails console`). No per-entry backfill is needed.

**Nothing constructs a provider URL outside a template.** The legacy `source`,
`source_two`, `preferred_source` and `subentries.source` columns were dropped on
2026-08-23; there is no fallback left, so a blank `embed_url` means the entry genuinely
cannot play. A template whose tokens cannot all be filled yields nil rather than a
truncated URL. `rails sources:audit` reports anything that stops resolving.

**Manual entries**: the form takes a pasted URL (`Entry#source_url`, virtual) and
`Source.classify_url` turns Drive/mega/YouTube/archive links into a direct provider plus
`source_key`; anything unrecognised goes to the catch-all `custom` provider.

**Known limitation:** `Subentry#calculate_absolute_episode_number` counts episodes within
one entry, but each season is its own entry here, so it returns the plain episode number.
Nothing active uses `%{absolute_episode}` — only the deactivated vidsrc-cc anime template
does — but reactivating that provider would need this fixed first.

---

## 5. Request flows

### 5.1 Home — `GET /` → `lists#index`
Three buckets: your lists, recently watched (via `user_entries.completed_at`), community
lists (public + subscribed, or everything if admin). Each card calls
`list.current_entry(current_user)` for its poster.

### 5.2 Channel page — `GET /lists/:id` → `lists#show`
`load_entries` builds `@entries` as a hash of **section name → entries**, grouped by
`params[:criteria]` — restricted to `ListsController::GROUPING_CRITERIA`
(`Position`, `Genre`, `Year`, `Watched`, `Rating`, `Category`, `Media`, `Length`), anything
else falls back to `Position`. Section order comes from the controller's `@sections`
(`sort_sections` handles the string/number key mix); views must use that local rather than
re-sorting the keys. Child lists are loaded from `child_relationships` and given a
singleton `position` method so they can be interleaved with entries.
`format.text` re-renders just the `lists/_entries` partial (used by the sort/filter JS).

### 5.3 Player — `GET /entries/:id/watch` → `entries#watch`
1. Writes the user's `UserListPosition.current_position` to this entry's position.
2. For series/anime: resolves `@current_subentry` via `UserEntryPosition`, then makes a
   **synchronous TMDB call** for episode details.
3. Computes `@embed_url` (§4); redirects back to the list with an alert if blank.
4. Renders `entries/watch` in `layouts/special_layout` with both sidebars
   (`shared/_sidebar` = channels + now playing, `shared/_entries_sidebar` = the list;
   `shared/_episodes_sidebar` for episodes).

Navigation around the player: `increment_current` / `decrement_current` move **episode**
for series/anime (via `UserEntryPosition`) and **entry** otherwise; `shuffle_current`
jumps to a random unwatched entry.

### 5.4 Finishing something
- `entries#complete` — toggles `UserEntry` completion; on completion advances the user's
  list position to the next entry. Renders the `entries/_completion_status` partial.
- `entries#review` / `#complete_without_review` — used by the review modal on reviewable
  lists; both end in `navigate_after_completion`, which redirects to the user's new
  current entry.

### 5.5 Adding content
| Path | Entry point | Notes |
|---|---|---|
| Search → add to open list | `search_controller.js` (TMDB, client-side) → `POST /lists/:list_id/entries` | `entries#create` re-fetches from OMDB, then `Entry.create_from_source` |
| Add a whole season | `episodes_controller.js` → `POST /lists/:id/add_season` | → `SeasonImporter`; one TMDB call (two for anime past season 1) |
| Add a single episode | `entries#create` with `season`/`episode`/`tmdb` | → `EpisodeImporter`, creating a standalone `media: "episode"` entry |
| Global navbar search | `list_search_controller.js` → `POST /lists/add_to_list` (JSON) | |
| Mobile | `mobile_search_controller.js` → `POST /lists/add_to_favorites` (JSON) | targets the user's `mobile: true` list |
| Top-rated episodes | `lists#top_entries` → `ImdbScraper` | scrapes IMDb search HTML |
| Watch without saving | `GET /watch_now?imdb=…` → `pages#watch_now` | transient, no DB write |

`Entry.create_from_source` normalizes OMDB payloads (`OmdbApi.normalize_omdb_data`) and, on
failure, records a `FailedEntry` and returns an error **string** — callers must check
`entry.is_a?(Entry)`.

### 5.6 Mobile
Detected by user-agent regex duplicated in `ListsController#mobile_request?` and
`EntriesController#mobile_request?`. Mobile requests render `*_mobile` views with
`layouts/mobile` (a separate 476-line layout with its own markup and templates).

---

## 6. Front end

- **No JS build step.** `config/importmap.rb` pins everything; controllers are eager-loaded
  by `app/javascript/controllers/index.js`.
- **Mustache templates live in the layouts** (`layouts/application.html.erb`,
  `layouts/mobile.html.erb`) as `<template id="…">` blocks; the search controllers look
  them up by id. If search results render blank, the template id and the controller's
  `document.querySelector` have drifted apart.
- **Stimulus controllers** (`app/javascript/controllers/`):
  `search` (in-list TMDB search), `list_search` (navbar), `mobile_search`,
  `episodes` (season/episode browser), `poster_selector`, `edit` (entry modal),
  `completed`, `sort`, `slider`, `view_toggle`, `randomize`, `trailer`, `hover_play`,
  `link`, `button`, `entry_anchor`, `entries_sidebar`, `auto_advance` (**countdown
  disabled in code**). Unused: `cinema`, `frame_loader`, `omdb`, `hello`.
- **`services/tmdb_search_behavior.js`** holds the six methods `list_search` and
  `mobile_search` share (`tmdbSearch`, `tmdbShow`, `showOverlay`, `handleClickOutside`,
  `hideResults`, `showToast`), applied to both prototypes with `Object.assign`. If you are
  looking for one of those methods, it is not in the controller file. It lives under
  `services/` because Stimulus eager-loads `controllers/` and would register a mixin as a
  controller. `search_controller` keeps its own copies — its versions differ.
- **`spec/javascript_modules_spec.rb`** is the only test coverage this JavaScript has. It
  is static: it fails on an unpinned bare import, a method defined twice in one file, and
  a `data-action` pointing at a method no controller defines. All three otherwise show up
  only in the browser console.
- **Font Awesome** is self-hosted from npm (pinned to 6.x; v7 renames icons). Its
  `scss/` and `webfonts/` are vendored under `node_modules`, and `rails font_awesome:copy`
  puts the fonts in `public/webfonts` during `assets:precompile` — `$fa-font-path` points
  there because Dart Sass cannot emit Sprockets' digested filenames.
- **SCSS** is compiled by Dart Sass, *not* Sprockets: `application.scss` →
  `app/assets/builds/application.css`. External imports need explicit load paths in
  `config/initializers/dartsass.rb` (Bootstrap from `node_modules`, Font Awesome from its
  gem). Run `bin/dev` in development — it starts `dartsass:watch` next to the server;
  `assets:precompile` handles the build on deploy.
- **SCSS** in `app/assets/stylesheets`: `config/` (variables, colors, fonts),
  `components/`, `pages/`, `themes/_light_mode.scss`. Dark mode is the default; the theme
  is a body class driven by `users.dark_mode`.

---

## 7. Services (`app/services/`)

| Service | Role |
|---|---|
| `OmdbApi` | OMDB lookups; rotates across `OMDB_API_KEY_1..3` by `sample`. Also fetches series episodes (TMDB when a `tmdb` id exists, else OMDB). |
| `EpisodeImporter` | one standalone `episode` entry from TMDB |
| `SeasonImporter` | a season: parent entry + a `Subentry` per episode, incl. anime absolute numbering |
| `ImdbEntryImporter` | one movie/series entry from an IMDb id via OMDB |
| `PosterCandidates` | poster options for the picker (TMDB, OMDB, recent list entries) |
| `TmdbService` | the TMDB client: typed endpoints (`fetch_show`, `fetch_season`, `fetch_episode`, `find_by_imdb_id`, …) through one `get_json` with timeouts, raising `TmdbService::RequestError`; plus trailers, posters and image URL validation |
| `ImdbScraper` | scrapes IMDb search results for top-rated episodes (HTTParty + Nokogiri) |
| `UrlCheckerService` | fetches a source URL and checks for a non-empty `<title>` → sets `entries.stream` |
| `ImageRepairService` / `PosterMigrationService` | fix broken `pic` URLs; copy `pic` → Active Storage/Cloudinary. Return `{status: :migrated|:repaired|:valid|:failed|:skipped|:error, message:}` — **status values are symbols** |
| `CsvImporterService` / `CsvExporterService` | seed/export via `db/seed_data/*.csv` |
| `DatabaseBackupService` / `DatabaseMigrationHelper` | `rake db:backup:*`, pg_dump + Active Storage manifest |
| `LetterboxdService` | OAuth + diary sync |

---

## 8. Background jobs

`LetterboxdBulkSyncJob` paces a whole-library sync against Letterboxd's rate limit.
Two more run from `Entry` `after_commit` callbacks:
`CheckEntrySourceJob` (validates a new entry's URL → `entries.stream`) and
`AttachPosterFromPicJob` (mirrors `pic` into Cloudinary).

**TMDB responses are cached** for 12 hours in a bounded per-process `:memory_store` — not
Redis, which is Sidekiq's and runs `noeviction` (cache growth there would fail enqueues).

**Production runs Sidekiq** (`config.active_job.queue_adapter = :sidekiq`) against the
Railway Redis service, in a **separate `worker` service**. Its start command —
`bundle exec sidekiq -C config/sidekiq.yml`, the same as the Procfile's `worker:` line —
is set in that service's Railway settings (Deploy → Custom Start Command), *not* in a
config file: Railway is retiring config-as-code (see §11). Keeping the worker separate
matters: the web start command runs `assets:precompile && db:migrate`, and two services
racing migrations is a real hazard.

- `config/sidekiq.yml` — concurrency 3, queues `default` and `mailers`. Concurrency must
  stay ≤ the Active Record pool (`RAILS_MAX_THREADS`, default 5).
- `config/initializers/sidekiq.rb` — points at `REDIS_URL` when set; otherwise Sidekiq's
  own localhost default.
- `ApplicationJob` sets `discard_on ActiveJob::DeserializationError` — jobs now outlive the
  process that enqueued them, so a record deleted between enqueue and perform is common.
- **Dashboard: `/sidekiq`**, mounted for admins only. Enqueued / retrying / dead jobs.

**Development still uses `:async`** (in-process, no Redis needed) and test uses `:test`, so
neither needs a local Redis.

---

## 9. External dependencies & keys

| Service | Used from | Key |
|---|---|---|
| TMDB | server (`OmdbApi`, `TmdbService`, 3 controllers) **and** browser (4 Stimulus controllers) | `TMDB_API_KEY` — server code goes through `TmdbService.api_key` (`ENV.fetch`, fails loudly); the browser reads `<meta name="tmdb-key">`, emitted by all three layouts |
| OMDB | server only | `OMDB_API_KEY_1..3` |
| Cloudinary | Active Storage | `CLOUDINARY_URL` |
| Letterboxd | OAuth flow | `LETTERBOXD_CLIENT_ID/SECRET/REDIRECT_URI` |
| IMDb | HTML scraping | none |

`docs/guides/ENVIRONMENT_VARIABLES.md` lists the full set.

---

## 10. Routes worth knowing

`config/routes.rb` — non-obvious ones:
- `lists`: member `watch_current` (GET), `top_entries` (POST), `add_season` (POST),
  `move_to_list`, `subscribe`, `unsubscribe`, `mark_all_complete/incomplete`;
  collection `search` (JSON).
- Two non-RESTful posts outside the resource: `/lists/add_to_favorites`, `/lists/add_to_list`.
- `entries` member routes are split by side effect: **writes are PATCH/POST**
  (`complete`, `review`, `complete_without_review`, `reportlink`, `repair_image`,
  `migrate_poster`, `duplicate`, `shuffle_current`, `increment_current`,
  `decrement_current`, `update_position`, `set_source`, `update_poster`) and only reads
  stay GET (`watch`, `fetch_posters`). CSRF tokens do not protect GET, so nothing that
  writes may be reachable that way. There is **no `index`** action.
  - `lists#watch_current` and `entries#watch` are the deliberate exceptions: they render
    or redirect to the player and write the user's position as a side effect of "I am
    watching this now". They are navigation targets, not actions.
  - The watch page sets `data-turbo="false"`, so its controls are `button_to` forms —
    `data-turbo-method` links would silently fall back to GET there.
- `sources` (admin only), `/watch_now`, `/health`, `/letterboxd/*`.

---

## 11. Deployment & operations

- **Railway.** Start commands live in each service's settings (Deploy → Custom Start
  Command), *not* in a config file — there is no `railway.json`, deliberately: a repo-root
  config applies to **every** service built from this repo and outranks the dashboard, so
  the worker could not override the web command. Config-as-code is also deprecated
  (Railway stops reading those files on 2026-12-01).
  - `how-to-watch`: `rails assets:precompile && rails db:migrate && rails server -b 0.0.0.0 -p $PORT`
  - `worker`: `bundle exec sidekiq -C config/sidekiq.yml`
  - Both are mirrored in the `Procfile` (`web:` / `worker:`), which is what Railway's
    builder falls back to when a service has no custom start command.
- Migrations run on every web boot, so a bad migration takes the app down.
- **Builders differ per service.** The worker builds with Railpack (Nixpacks is deprecated);
  Railpack's final image is minimal, so gems with native extensions need their shared
  libraries declared: `RAILPACK_DEPLOY_APT_PACKAGES=libffi8 libpq5` is set on both services.
  It is ignored by Nixpacks, so it is safe to carry on a service that has not migrated yet.
- Health check: `GET /health` (the only unauthenticated action).
- **Security headers**: `Permissions-Policy` is enforced (`config/initializers/permissions_policy.rb`)
  and denies features the app never uses, which also limits the embedded player.
  `Content-Security-Policy` is **report-only** — see that initializer for what has to change
  before it can be enforced.
- Production forces SSL, allows `*.railway.app` and `RAILS_HOST`.
- The `worker` service shares the app's env via Railway references; it needs
  `DATABASE_URL`, `REDIS_URL`, `RAILS_MASTER_KEY`, `SECRET_KEY_BASE`, `CLOUDINARY_URL`
  and the TMDB/OMDB keys.
- Useful rake tasks: `sources:seed`, `sources:backfill`, `entry:check_sources`,
  `images:check` / `images:repair`, `positions:fix_invalid`, `db:backup:full`,
  `db:backup:restore[file]`, `export:entries`.
- Task guides live in `docs/guides/` (Railway deploy, backups, image repair, poster
  migration, Letterboxd). Written Sept 2025 — treat as historical.

---

## 11a. Tests

RSpec is the live suite (`bundle exec rspec` — 31 examples). `spec/rails_helper.rb` calls
`Rails.application.reload_routes_unless_loaded` because Rails 8 draws routes lazily and
Devise registers its mappings during that draw; without it every `sign_in` fails. The test
env uses the `:test` job adapter, since entry callbacks enqueue network-touching jobs.
The `test/` Minitest tree is leftover generator stubs and does not run clean.
`bundle exec rubocop` works again (~1,169 mostly-style offenses, not yet addressed).

---

## 12. Uncommitted work in the tree (as of 2026-08-21)

Not yet committed, and it matters when reading `git log`:
- `app/jobs/check_entry_source_job.rb` — **new, untracked**.
- `Entry`: callbacks moved to `after_commit`, `normalize_media` added, source check moved
  into the job, poster attach always async.
- `UrlCheckerService`: open/read/total timeouts + 64 KB read cap.
- `Source#template_for` downcases the media key; `db/seeds/sources.rb` gains an anime
  template for vidsrc.ru.
- Two migrations already reflected in `schema.rb`: `fix_vidsrc_ru_tv_templates`,
  `normalize_entry_media_case`.

---

## 13. Debugging map — symptom → where to look

| Symptom | Start here |
|---|---|
| List page 500s while grouping | `ListsController#filter_entries` + `sort_sections`; nullable `genre`/`year`/`rating` are the usual cause. |
| Player is blank / "No video source available" | `Entry#embed_url` → `#resolved_source` → the `Source` row's `templates`; then `Entry#legacy_embed_url`. Check the source is `active` and its template has a key for that `media`. |
| Wrong episode plays | `UserEntryPosition` for that user+entry; `Entry#current_subentry_for_user`; for anime, `Subentry#calculate_absolute_episode_number`. |
| Episode numbers off for anime | anime may use absolute numbering (`%{absolute_episode}`); note `calculate_absolute_episode_number` counts within one entry, and each season is its own entry here. |
| "Watched" state wrong or resets | `UserEntry` (not `entries.completed`). Note `Entry#user_entry_for` **creates** a row on read. |
| List starts on the wrong item | `UserListPosition.current_position` vs `entries.position`; `rails positions:fix_invalid`. `lists.current` is legacy and ignored per-user. |
| Entry order looks scrambled | three competing schemes: `Entry.next_position`, `list.entries.count + 1`, `shift_positions`, `List#normalize_entry_positions!`. |
| Poster missing / broken image | `entries.pic` vs the Active Storage `poster`; `AttachPosterFromPicJob` (in-process, easily lost); `ImageRepairService`; `ImageHelper#entry_poster_image_tag` builds Cloudinary URLs by hand. |
| Search returns nothing | client-side TMDB fetch in the Stimulus controller (check the browser console + the `<template>` id in the layout), not the server. For `list_search`/`mobile_search` the fetch itself is in `services/tmdb_search_behavior.js`. |
| A button or input does nothing at all | a `data-action` naming a method that no longer exists — Stimulus reports it only in the console. `bundle exec rspec spec/javascript_modules_spec.rb` catches every instance. |
| Filtering a list returns everything | `ListsController#load_entries` builds `@position_items`; the default `Position` view renders that rather than the grouped `@entries`, so a filter has to be applied there too. |
| Adding a series creates no episodes | `OmdbApi.get_series_episodes` → needs `entry.season` and (ideally) `entry.tmdb`. Failures here surface as the misleading flash "This already exists in your list". |
| Sort/group setting doesn't stick | `ListsController#load_entries` — writes are guarded to explicit params, and `settings` is read back as the default. |
| Slow list page | check the preloads first: `ListsController#with_card_data` (index) and the `includes(:user_entries)` in `load_entries` (show). Losing either turns `completed_by?` / `current_entry` back into a query per row. `find_now_playing_for_sidebar` also runs on every page. |
| Worker crashes at boot with `libffi.so.8: cannot open shared object file` | Railpack's runtime image lacks libffi, which `sassc-rails → sassc → ffi` needs at Rails boot. Fixed with `RAILPACK_DEPLOY_APT_PACKAGES=libffi8 libpq5` on the service. `/mise/installs/...` paths in a trace mean Railpack; `/nix/store/...` means Nixpacks. |
| Job "didn't run" | check `/sidekiq` (admin) for retries/dead jobs, then `railway logs --service worker`. In development jobs run on `:async` in-process, so a dev-only failure is a different animal. |
| Mobile layout differs from desktop | user-agent sniffing in both controllers → `*_mobile` views + `layouts/mobile`. |
| Admin-only UI missing | `users.admin`; sources CRUD and default-list toggles are admin-gated. |
