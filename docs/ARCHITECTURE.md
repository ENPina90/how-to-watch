# How To Watch — Architecture & Operations Reference

**Purpose:** the map of this codebase. Read this before diagnosing anything; the last
section ("Debugging map") goes from symptom → the file that actually owns the behavior.

**Last verified:** 2026-09-11 against `master` @ `1ac4aef`.

---

## 1. What the app is

A personal/social "channel surfing" app. Users build **lists** (channels) of movies,
series, anime, standalone episodes and fanedits, then play them in an embedded iframe
from third-party streaming providers. Progress (what you've watched, where you are in a
list, which episode you're on) is tracked **per user**, so several users can watch the
same list independently.

Metadata comes from TMDB and OMDB; posters are mirrored into Cloudinary; playback URLs
are generated from provider URL templates.

Built on top of that, and newer: **cable** (§5.9), where a channel plays to a schedule and
you join whatever is already running; **watch parties** (§5.10), where a room watches
together with the host's player as the clock; **voting** (§5.11) on what to put on; and an
**admin dashboard** (§5.14) with the sweeps that tell an admin when a provider, a poster or
an embed has stopped working.

The distinction worth holding on to is that the original app is per-viewer in every
respect, and cable is per-viewer in none of them.

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
| Redis | Railway `Redis` service on the private network; used by Sidekiq **and by Action Cable**, which watch parties depend on (§5.9) |
| Periodic | `sidekiq-cron`, schedule in `config/schedule.yml`, registered on the Sidekiq **server** only (§8) |
| Hosting | Railway: `how-to-watch` (web) + `worker` (Sidekiq), plus `Postgres` and `Redis` |

---

## 3. Domain model

### 3.1 Core content

**`User`** — Devise account. Flags: `admin` (can edit anything, manage `Source`s, set
default lists, and **view the site as another user** — §5.7), `dark_mode`, `letterboxd_enabled`. On create it
auto-subscribes to default lists and **creates a "<Name>'s Watchlist" list** with
`mobile: true, private: true`, then points `favorite_list_id` at it
(`User#create_default_list`).
- `favorite_list_id` → `List`: **the member's favourite channel** — where
  `/lists/add_to_favorites` files an entry and what the mobile index opens on. One column,
  so there is only ever one; validated to a list the member owns (`favorite_list_is_own`),
  and nullified rather than cascading if that list is deleted. Set from the channel's edit
  page via `PATCH /lists/:id/toggle_favorite`, which checks ownership itself because
  `can_edit_list?` also lets anyone edit a default channel. `User#favorite?`, `#favorite!`
  (moves it), `#unfavorite!`.

**`List`** — a channel. Owned by a user.
- `ordered` — true: play in `position` order; false: play a random unwatched entry.
- `private`, `default` (admin-set; everyone auto-subscribes), `mobile` (marks the channel
  created with the account; a record of where it came from, not what it is for — the
  favourite is `users.favorite_list_id`), `reviewable` (prompt for a rating after
  finishing).
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
| `UserEntry` | user × entry | `completed`, `completed_at`, `last_watched_at`, `review` (1–10), `comment`, `player_progress` (seconds, §5.8) |
| `UserListPosition` | user × list | `current_position` (an `entries.position` value) |
| `UserEntryPosition` | user × entry | `current_subentry_id` — which episode you're on |
| `Subscription` | user × list | which channels appear in your sidebar |

**Reads must not write.** `Entry#user_entry_for` / `List#position_for_user` are lookups
returning nil; the `!` variants (`user_entry_for!`, `position_for_user!`) create. Both reads
use the preloaded association when the caller eager-loaded it, so controllers that render
many entries should `includes(:user_entries)` / `includes(:user_list_positions)`.

Rule of thumb: **anything user-specific is in one of these four tables** — and note the
two places that deliberately read none of them: `/cable` (§5.9) and the guide, where what
plays is a question about the clock rather than about you.

The columns `entries.completed`, `lists.current`, and `entries.current_id` are the
pre-multi-user versions and are only touched by legacy paths.

### 3.3 Dead / legacy tables still in the schema

`follows`, `list_user_entries` (superseded by `subscriptions` + `user_list_positions`),
`failed_entries` (write-only error log from CSV/OMDB imports).

### 3.4 Everything else in the schema

Added after the core above, and each one is the subject of its own request flow in §5.

| Model | What it is |
|---|---|
| `CableSlot` | one programme in one channel's day: entry, `starts_at`/`ends_at`, optional `subentry`, optional `break_reel`. **Identical for every viewer** — see §5.9 |
| `CommercialReel` | an advert that fills the gap between programmes on `/cable`. Admin-managed under `/admin/commercial_reels` |
| `WatchParty` + `WatchPartyMembership` | a room watching the same thing at once, addressed by `token`. §5.10 |
| `VoteSession` + `VoteOption` + `Vote` | one round of voting on a channel: a shortlist on a screen, phones voting via QR. §5.11 |
| `Notification` | something the app wants to tell one person. §5.12 |
| `AppSetting` | the site's own switches, **as a single row** — access mode and the up-next threshold. §5.13 |
| `Visit` | deliberately thin traffic counting for the admin dashboard: a cookie token, a day, a page count, an optional user id. No path, no referrer, no address |
| `Current` | `ActiveSupport::CurrentAttributes`; memoises `AppSetting.current` for the length of a request |

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

**A `Source` also carries, beyond its templates:**
- **Expiry.** `valid_until` makes a source *perishable*; `expired?` / `expiring_soon?` /
  `expiry_state` / `days_until_expiry` read it and `renew!` pushes it out. A daily
  `SourceExpiryScanJob` warns admins through a `Notification` before a domain lapses.
- **Order.** `Source.reorder!` sets the `position` admins drag them into, which is also the
  order `resolved_source` falls back through.
- **Sync adapters.** `SYNC_ADAPTERS[slug]` → `sync_adapter`, and `syncable?` is what decides
  whether a watch party can actually drive a provider's player (§5.10). Alongside it:
  `resume_param` / `resumable?` (start a film part-way in, which is how `/cable` joins a
  programme already running and how up-next resumes), `subtitle_param` (cable turns
  subtitles off by default) and `preconnect_origins` (emitted on the player page).
- **`probe_url` / `probe_label`** back `GET /sources/:id/test`: play a known title through
  this provider alone, to answer "is this domain still up" without hunting for an entry.

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
| Add a whole season | `episodes_controller.js` → `POST /lists/:id/add_season` | → `SeasonImporter`; one TMDB call (two for anime past season 1) |
| Add a single episode | `entries#create` with `season`/`episode`/`tmdb` | → `EpisodeImporter`, creating a standalone `media: "episode"` entry |
| Global navbar search | `list_search_controller.js` → `POST /lists/:list_id/entries` | `entries#create` re-fetches from OMDB, then `Entry.create_from_source`. Off a channel page it asks the picker which channel first |
| "+ Details" on a search result | `list_search_controller.js#details` → `GET /lists/:id/entries/new?imdb=…` | → `EntryPrefill`. **Creates nothing**: the form opens filled in and the row exists only once Create Entry is pressed |
| By hand | `GET /lists/:id/entries/new` → `entries#create` with `custom` | The custom-entry form: a fanedit, a personal cut, anything the APIs describe badly. No search box of its own |
| A spreadsheet of them | `GET .../entries/csv_template`, `POST .../entries/import_csv` | → `EntryCsvTemplate` / `EntryCsvImporter`; inside the request, capped at `MAX_ROWS` |
| Mobile | `mobile_search_controller.js` → `POST /lists/add_to_favorites` (JSON) | targets `current_user.favorite_list`; 404s when there is none |
| Top-rated episodes | `lists#top_entries` → `ImdbScraper` | scrapes IMDb search HTML |
| Watch without saving | `GET /watch_now?imdb=…` → `pages#watch_now` | transient, no DB write |

The `/entries/new` page used to carry a second search of its own (`search_controller.js`,
its own mustache card templates, a Movie/Series/Anime tab row). It does not any more: the
navbar search is on every page, and its "+ Details" button reaches this form with the
metadata already in it. The page is now only the manual form plus the CSV round trip.

`Entry.create_from_source` normalizes OMDB payloads (`OmdbApi.normalize_omdb_data`) and, on
failure, records a `FailedEntry` and returns an error **string** — callers must check
`entry.is_a?(Entry)`.

### 5.6 View as another user (admins)
`app/controllers/concerns/impersonation.rb`, included by `ApplicationController`.
`current_user` is what every permission check reads (`admin?`, `can_edit_list?`, the four
per-user tracking tables), so the concern overrides it to return the impersonated user
and keeps the real account in **`true_user`**. There is no parallel "pretend" code path,
which is the point: what the admin sees is what that user's own session renders.

- Start/stop: `POST /impersonate/:id` / `DELETE /impersonate` (`ImpersonationsController`).
  The admin check reads `true_user`, so switching straight from one user to another works.
- UI: `shared/_impersonation_menu` in both navbars (application + mobile) and
  `shared/_impersonation_banner` in all three layouts — the watch page's
  `special_layout` has no navbar, so the banner is the only way out from there.
- `true_user` is deliberately confined to that concern, the two partials and the
  controller. Anywhere else it would show the admin something the real user's session
  would not, which defeats the whole feature.
- **Writes land on the impersonated user.** Marking something watched, the dark-mode
  toggle, a Letterboxd sync — all of it hits their rows, because that is the same code
  path they run. This is for checking what a page looks like, not a read-only preview.
- `/sidekiq` is mounted through Devise's route-level `authenticate`, which only ever sees
  the Warden user (still the admin). The extra `constraints` lambda in `config/routes.rb`
  on the session key is what actually hides it while impersonating.

### 5.7 Mobile
Detected by user-agent regex duplicated in `ListsController#mobile_request?` and
`EntriesController#mobile_request?`. Mobile requests render `*_mobile` views with
`layouts/mobile` (a separate 476-line layout with its own markup and templates).

---

### 5.8 Progress and up next

`UserEntry#player_progress` holds where the viewer got to, in seconds. It is written by
`POST /entries/:id/progress` — **POST rather than PATCH because `navigator.sendBeacon`,
which is how the position is saved as the page goes away, can only send POST.**

Completion is a fraction of runtime, not a position: `UserEntry::COMPLETION_FRACTION`
(0.95). `AppSetting#up_next_fraction` decides how far in the up-next card appears, and is
validated into `UP_NEXT_RANGE`, which **floors at the completion fraction**. Below that
floor the fullscreen path stops raising the card at all, silently — the floor exists to
prevent exactly that. `PATCH /entries/:id/runtime` is the player correcting the catalogue
when a file turns out to run to something other than what TMDB said.

### 5.9 Cable — `GET /cable`, `GET /cable/:id`, `GET /cable/guide`

Channels that are **already running** when you turn them on. This is the one part of the
app where nothing is per-viewer, and the module comment in `app/services/cable_schedule.rb`
is emphatic about why: two people opening the same channel at the same second must see the
same frame, so nothing here reads `UserListPosition`, `UserEntryPosition` or
`player_progress` — **and nothing here writes them either.** Marking something watched is
the one exception and it goes out through the ordinary `entries#complete` route, because
that is something the viewer chose rather than a side effect of rendering a page.

- A day is laid out in advance into `cable_slots`, entries shuffled and laid end to end
  from midnight to midnight in `CableSchedule::DEFAULT_ZONE` (`America/Toronto`, overridable
  with `CABLE_TIME_ZONE`) — not UTC, so "tomorrow" means the viewer's tomorrow.
- Slots start and end on a five-minute grid (`BREAK_GRID`), so a listing reads 8:00 and 9:05
  rather than 8:07 and 9:53. Whatever is left between the film ending and the next mark is a
  commercial break, filled by a `CommercialReel`. A break is 0–4 minutes, never more.
- Runtime gaps are guessed (`FALLBACK_MINUTES`, 100 for a film, 30 otherwise) rather than
  dropping the entry, and `MIN_MINUTES` (5) keeps bad catalogue data from filling a day with
  thousands of rows. `MAX_SLOTS_PER_DAY` (200) is the backstop.
- `CableScheduleJob` deals tomorrow daily and fills today **only if it is empty**
  (`ensure_day!` leaves an existing schedule alone, so it can never pull a running programme
  out from under anybody). `CableSchedule.prune!` keeps `RETAIN_DAYS` (2).
- `cable#show` and `cable#guide` also call `ensure_day!` on the way through, so the dial
  never has a dead channel on it after a deploy or a newly-defaulted channel.
- **Route order is load-bearing**: `get 'cable/guide'` must stay above `get 'cable/:id'`, or
  "guide" is read as a channel id, cast to nothing, and quietly serves channel one.
- The guide renders in the *viewer's* zone (`params[:tz]`) even though the schedule itself
  is a set of fixed instants.
- **The way off a channel** is `watch_entry_path(entry, channel:, subentry:)` — the ordinary
  player, from the beginning, counting towards what the viewer has seen. Three things offer
  it: the banner's headline, the guide panel's, and the "Start from the beginning" button in
  each of those (`cable-hud__start`, `tvguide__start`). The buttons follow whatever is being
  *described* rather than whatever is playing, so the banner's arrows and a pointer moving
  across the grid both re-aim them. None of the three carries `data-cinema-move`, so all
  three are navigations out of cable rather than a change of channel.
- **`CableSchedule.on_air_now`** is the whole dial in one query — every channel with
  something on, paired with its slot and its number, shaped like `guide`'s rows. It exists
  for the sidebar's Now Playing card (§6), which asks it on every page that draws a sidebar.

### 5.10 Watch parties — `resources :watch_parties, param: :token`

The only Action Cable feature, and the only reason the `redis` gem is pinned (see the
Gemfile comment: Action Cable's pubsub adapter declares `redis < 6`, so on 6.x every
broadcast raises `Gem::LoadError` while the socket still connects and the subscription still
takes — nothing is ever delivered).

- The **host's player is the clock**: it reports where it is and everyone else is moved to
  match. When the host changes episode the whole room follows.
- Addressed by `token` rather than id, because the token *is* the invitation — `show` is the
  link people paste to each other.
- `WatchPartyContext` keeps the token in the **session**, so a room follows the person
  around the site instead of belonging to one page, and drops a token whose party has closed
  so a dead room does not put a bar on every page.
- Only providers where `Source#syncable?` can actually be driven. On the rest the party
  still holds everyone on the same entry and shows how far apart they are; it just cannot
  close the gap.
- `CloseAbandonedWatchPartiesJob` runs every 15 minutes. `ABANDONED_AFTER` is 2 minutes,
  comfortably longer than the 45-second presence staleness, because a reload is a disconnect
  too; the `created_at` age check keeps a room from being reaped in the seconds between the
  host opening it and their browser opening the socket.

### 5.11 Voting — `resource :vote` nested under a list

A shortlist put on one screen, voted on by the phones in the room via a QR code (`rqrcode`).
`VoteSession.open_for(list, count)` replaces whatever round was open and draws its options
**at random** rather than taking the first few — the point is to decide between things
nobody has already picked out. `standings` breaks ties by ballot order so a tie reads the
same way twice instead of shuffling under whoever refreshes. `VotesController` deliberately
**skips `AccessControl`**: a room scanning a QR code is a different question from who may
browse the site.

### 5.12 Notifications — `resources :notifications`

Deliberately generic, so a second table is never needed: `kind` says what sort of thing it
is, polymorphic `subject` points at what it is about, and anything kind-specific lives in
`data`. Kinds so far are all admin-facing sweep results — `source_expiring`,
`broken_poster`, `unplayable_embed`, `missing_runtime` — and `ADMIN_ONLY_KINDS` is enforced
**on write and again on read**, so an account that loses its admin flag stops seeing them
without needing a sweep.

`dedupe_key` is what makes dismissal safe for a warning that is really a *state* rather than
an event: it carries the date being warned about, so renewing a provider retires the
dismissed row and a later warning about the new date is a new notification.

### 5.13 Who gets in without an account

`AppSetting#access_mode` is one of `secure` (nothing — sign in first), `moderate` (browse:
the channel index, a channel's page, search) or `open` (browse **and** watch). Writes always
need an account: there is nowhere to record a position, a review or a new channel without
one.

The permitted actions are a table in `app/controllers/concerns/access_control.rb` rather
than declarations scattered across controllers, so the whole answer to "what can a stranger
reach" reads top to bottom. Two rules hold it down whatever the table says: **only GETs are
ever allowed through**, and **anything unlisted falls through to Devise**, so a new
controller is closed until somebody decides otherwise.

`AppSetting` is a single row, enforced by an `only_row` validation — every reader takes
`first`, so a second row would be settings nobody can see and an edit that appears to do
nothing. It is created on first read, so a fresh database needs no seed, and memoised per
request through `Current`.

### 5.14 Admin dashboard — `/admin`

`Admin::BaseController` turns away everyone else. The dashboard shows `AdminStatistics`
(counts and grouped counts over one seven-day window, gathered so the view holds no
queries), the site switches, and buttons that run the poster and embed sweeps on demand —
the same jobs the weekly schedule runs, so there is one implementation and one set of
results. `POST reset_source` moves every channel onto one provider.
`Visit` backs the traffic figures.

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
- **The sidebar's Now Playing card** (`shared/_sidebar`) answers two different questions
  depending on where it is drawn. On the player there is a picture beside it and the card is
  a caption for that picture: it names `@entry`, and `cinema_navigation_controller` swaps
  `#nowPlayingContent` along with the frame and the chrome when the viewer changes channel.
  Everywhere else nothing of theirs is playing, so it shows the **cable dial** — whatever is
  on air this second — and pressing it tunes to that channel. Which channel rotates, one
  step per render, from a position kept in the session
  (`ApplicationController#cable_now_playing`). It falls through to the stand-by card only
  when the whole dial is dark.
- **Modals are page-level, never per card.** The trailer modal, the poster picker and
  the review modal are rendered **once** per list page (`shared/_trailer_modal`,
  `shared/_poster_selector_modal`, `entries/_review_modal_list`). Each is opened by a
  plain Bootstrap trigger on the card, and its controller reads the entry off
  `event.relatedTarget` in `show.bs.modal` -- so the markup holds nothing entry-specific
  and one modal serves every card. They used to be rendered inside the card partials:
  on a 1,203-entry list that was 3,610 modals, 1,203 `<iframe>`s and 1,202 copies of the
  same script, 12.7 MB of HTML and ~3.8s of view rendering with the query count already
  flat. **Do not put a modal, a `form_with`, or an inline `<script>` in an entry card
  partial** (`entries/_entry_movie` and its four siblings) -- each one is paid ~1,200
  times. `spec/requests/list_show_payload_spec.rb` fails if a per-entry modal comes back.
  The watch page is the exception: it shows one entry, so it keeps its own
  `entries/_review_modal` with turbo disabled, answering the same `#reviewModal` id.
- **`services/tmdb_search_behavior.js`** holds the six methods `list_search` and
  `mobile_search` share (`tmdbSearch`, `tmdbShow`, `showOverlay`, `handleClickOutside`,
  `hideResults`, `showToast`), applied to both prototypes with `Object.assign`. If you are
  looking for one of those methods, it is not in the controller file. It lives under
  `services/` because Stimulus eager-loads `controllers/` and would register a mixin as a
  controller. `search_controller` keeps its own copies — its versions differ.
- **`spec/javascript_modules_spec.rb`** is the only test coverage this JavaScript has. It
  is static: it fails on an unpinned bare import, a method defined twice in one file, a
  `data-action` pointing at a method no controller defines, and a `data-*-target` no
  controller declares. All of those otherwise show up only in the browser console — or
  not at all, since Stimulus ignores an undeclared target silently.
- **Font Awesome** is self-hosted (pinned to 6.7.2; v7 renames icons). Its `scss/` is
  vendored in `vendor/sass/`, and the webfonts are committed to `public/webfonts` and
  served straight from there — `$fa-font-path` points at `/webfonts` because Dart Sass
  cannot emit Sprockets' digested filenames.
- **SCSS** is compiled by Dart Sass, *not* Sprockets: `application.scss` →
  `app/assets/builds/application.css`. External imports need explicit load paths in
  `config/initializers/dartsass.rb`, which points at `vendor/sass/` — Bootstrap's and Font
  Awesome's Sass sources, copied from the npm packages of the same versions and committed.
  They are not read from `node_modules` and not taken from the `bootstrap` /
  `font-awesome-sass` gems: node is absent from one Railway builder at precompile time
  (see the deployment guide), and both gems depend on `sassc`, the `ffi` chain #28 removed.
  Run `bin/dev` in development — it starts `dartsass:watch` next to the server;
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
| `EntryPrefill` | Builds an **unsaved** Entry from OMDB (or TMDB, for a standalone episode) for the custom-entry form to open filled in |
| `EntryCsvTemplate` / `EntryCsvImporter` | The blank sheet `/entries/new` hands out and reads back. `COLUMNS` is the contract between them; a row with an `imdb` id is looked up and what was typed wins over what the lookup said |
| `CsvImporterService` / `CsvExporterService` | seed/export via `db/seed_data/*.csv` — the *seed* pair, unrelated to the two above |
| `DatabaseBackupService` / `DatabaseMigrationHelper` | `rake db:backup:*`, pg_dump + Active Storage manifest |
| `LetterboxdFeed` | Reads a member's public Letterboxd diary (RSS) |
| `LetterboxdList` | Reconciles that diary into a channel |
| `LetterboxdFilm` | Builds links to a film on Letterboxd |
| `CableSchedule` | Lays out and reads the cable day (§5.9). `module_function`, no per-user state |
| `CommercialCatalog` | The reels available to fill a break |
| `SourceCatalog` / `ChannelSourceReset` | The provider list; moving every channel onto one provider |
| `VidsrcAvailability` / `VidsrcCatalog` | Asks VidSrc whether it actually holds a file for an entry |
| `EmbedAvailabilityAudit` / `UnplayableEmbedNotifier` | The sweep behind `embed_availability_scan`, and the notifications it raises |
| `PosterAudit` / `BrokenPosterNotifier` | Same shape, for posters whose image has gone |
| `MissingRuntimeAudit` / `MissingRuntimeNotifier` | Same shape, for scheduled entries cable has to guess a runtime for |
| `SourceExpiryNotifier` | Warns admins before a provider domain lapses (§4) |
| `AdminStatistics` | The dashboard's numbers, one seven-day window throughout |
| `DeploymentStatus` | Which build is actually running, recorded by the worker at boot |
| `YoutubeVideoFacts` | Reads a commercial reel's runtime off YouTube |
| `GoogleImageSearch` / `RemoteImage` | Extra poster sources; fetching and validating a remote image |

---

## 8. Background jobs

Two run from `Entry` `after_commit` callbacks: `CheckEntrySourceJob` (validates a new
entry's URL → `entries.stream`) and `AttachPosterFromPicJob` (mirrors `pic` into
Cloudinary). `LetterboxdSyncJob` refreshes one member's Letterboxd channel on demand.

**The rest are periodic**, registered from `config/schedule.yml` by `sidekiq-cron`:

| Job | When (UTC) | What |
|---|---|---|
| `CableScheduleJob` | daily | Deal tomorrow for every channel; fill today if empty (§5.9) |
| `CloseAbandonedWatchPartiesJob` | every 15 min | Close rooms nobody has open (§5.10) |
| `SourceExpiryScanJob` | daily | Warn admins about lapsing provider domains |
| `LetterboxdWeeklyRefreshJob` | Mondays | Re-read every linked member's diary |
| `BrokenPosterScanJob` | Mondays | Poster URLs that no longer answer with an image |
| `EmbedAvailabilityScanJob` | Tuesdays | Entries VidSrc has no file for |
| `MissingRuntimeScanJob` | Wednesdays | Scheduled entries cable must guess a runtime for |

The schedule is loaded **on the Sidekiq server only** (`config/initializers/sidekiq.rb`) —
a web process registering them too would have several dynos racing to own the same
schedule. Registration touches Redis and is wrapped in a rescue: a failure there would
otherwise take the whole worker down at boot, and processing queued jobs matters more than
a weekly refresh the next restart will register anyway. The same hook calls
`DeploymentStatus.record_worker!`, so the dashboard can show which build is actually
running rather than which was last deployed.

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
| Letterboxd | Public RSS diary (no auth) | — |
| IMDb | HTML scraping | none |

`docs/guides/ENVIRONMENT_VARIABLES.md` lists the full set.

---

## 10. Routes worth knowing

`config/routes.rb` — non-obvious ones:
- `lists`: member `watch_current` (GET), `top_entries` (POST), `add_season` (POST),
  `move_to_list`, `subscribe`, `unsubscribe`, `mark_all_complete/incomplete`,
  `toggle_default`, `toggle_favorite`; collection `search` (JSON).
- Two non-RESTful posts outside the resource: `/lists/add_to_favorites`, `/lists/add_to_list`.
- `entries` nested under a list: `new` / `create`, plus collection `csv_template` (GET — it
  only generates a file) and `import_csv` (POST — it writes a spreadsheet's worth of rows,
  and `check_list_edit_permissions` asks whose channel it is first).
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
- `sources` (admin only) — plus member `renew` / `deactivate` (both PATCH: they change how
  the app plays things) and `test` (GET: it only plays something), and collection `reorder`.
- `/cable`, `/cable/:id`, `/cable/guide` — all GET, none of them write. **`cable/guide` must
  stay declared above `cable/:id`** (§5.9).
- `watch_parties`, keyed by `param: :token` rather than id (§5.10).
- `resource :vote` nested under a list, with `cast` / `close` / `remove_option` (§5.11).
- `notifications` with member `dismiss` and collection `dismiss_all` (§5.12).
- `namespace :admin` — `dashboard` (`show` / `update`, plus `reset_source`,
  `run_poster_scan`, `run_embed_scan`, all POST because they enqueue or rewrite) and
  `commercial_reels` (§5.14).
- `resource :profile` — the account page; email and password stay with Devise.
- `/watch_now`, `/health`, `/letterboxd/*` (`check` is reachable signed out, because the
  sign-up form asks before the account exists).

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

RSpec is the live suite (`bundle exec rspec` — **~1,370 examples, green, under a minute**). `spec/rails_helper.rb` calls
`Rails.application.reload_routes_unless_loaded` because Rails 8 draws routes lazily and
Devise registers its mappings during that draw; without it every `sign_in` fails. The test
env uses the `:test` job adapter, since entry callbacks enqueue network-touching jobs.
The `test/` Minitest tree is leftover generator stubs and does not run clean.
`bundle exec rubocop` works but has never been brought to clean (~5,000 mostly-style
offenses, ~4,550 autocorrectable). Do **not** run a blanket `-a`/`-A`: it would rewrite
nearly every file in the repo and bury whatever real change it was run alongside.

Specs worth knowing about, because they encode decisions rather than behaviour:
`javascript_modules_spec.rb` (§6 — the only coverage the JS has),
`list_show_payload_spec.rb` and the two `*_queries_spec.rb` files (§6, per-card cost and
query counts), and `entry_write_verbs_spec.rb` / `list_write_verbs_spec.rb` (§10, that
nothing which writes is reachable by GET).

---

## 12. Keeping this document honest

Everything above was read out of the code at the verification date in the header. The
sections most likely to drift, in order: §7 (services are added often), §8 (so are periodic
jobs), §4 (providers die and `Source` grows options), and §5.9 (cable is the newest part of
the app and still moving).

If you are reading this well after that date, `git log --stat docs/ARCHITECTURE.md` will
tell you how far behind it is likely to be. Trust the code; update the section you touched.

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
| Slow list page, but the query count is flat | it is the views, not the DB. See §6: anything rendered *per card* is multiplied by the list size, and the big lists run past a thousand entries. |
| Slow list page | check the preloads first: `ListsController#with_card_data` + `resolve_card_entries` (index) and the `includes(:user_entries).with_attached_poster` in `load_entries` (show). Losing either turns `completed_by?` / `current_entry` back into a query per row. `find_now_playing_for_sidebar` also runs on every page. **A preload here is easy to defeat without touching it:** anything that reloads the association (`all_items_by_position` did) throws it away silently. `spec/requests/list_show_queries_spec.rb` and `list_index_queries_spec.rb` assert the query counts stay flat. |
| A write succeeds that shouldn't | `EntriesController#check_edit_permissions` — it guards only the actions named in its `before_action`. Actions writing *shared* entry state belong there; the per-user ones (`complete`, `review`, current-position) deliberately do not. |
| Worker crashes at boot with `libffi.so.8: cannot open shared object file` | Railpack's runtime image lacks libffi, which `sassc-rails → sassc → ffi` needs at Rails boot. Fixed with `RAILPACK_DEPLOY_APT_PACKAGES=libffi8 libpq5` on the service. `/mise/installs/...` paths in a trace mean Railpack; `/nix/store/...` means Nixpacks. |
| Job "didn't run" | check `/sidekiq` (admin) for retries/dead jobs, then `railway logs --service worker`. In development jobs run on `:async` in-process, so a dev-only failure is a different animal. |
| Mobile layout differs from desktop | user-agent sniffing in both controllers → `*_mobile` views + `layouts/mobile`. |
| A cable channel is off air / a gap in the guide | nobody laid that day out. `CableSchedule.ensure_day!` runs from `cable#show`, `cable#guide` and `CableScheduleJob`; check the worker ran and that the channel is `default`. |
| Cable shows a different programme to two people | something read a per-user table. Nothing under §5.9 may touch `UserListPosition`, `UserEntryPosition` or `player_progress`. |
| A programme runs far too long or too short | no runtime in the catalogue, so `CableSchedule::FALLBACK_MINUTES` guessed. `MissingRuntimeScanJob` reports these; `PATCH /entries/:id/runtime` corrects one. |
| `/cable/guide` serves channel one | the `cable/guide` route slipped below `cable/:id` (§5.9). |
| Watch party connects but nothing ever arrives | the `redis` gem resolved to 6.x — Action Cable's adapter declares `< 6` and every broadcast raises `Gem::LoadError` while the socket still looks healthy (§5.10). |
| A watch party will not keep guests in step | `Source#syncable?` is false for that provider; the room can only hold everyone on the same entry. |
| A room vanishes while people are in it | `CloseAbandonedWatchPartiesJob` + `WatchParty::ABANDONED_AFTER`; check `last_seen_at` on the memberships. |
| Up-next card never appears in fullscreen | `AppSetting#up_next_fraction` set below `UserEntry::COMPLETION_FRACTION` — `UP_NEXT_RANGE` exists to floor exactly this (§5.8). |
| Progress is not saved when the tab closes | `POST /entries/:id/progress` — `sendBeacon` can only POST; a PATCH route here silently drops the write. |
| A dismissed warning keeps coming back (or never does) | `Notification#dedupe_key` — it carries the date warned about, by design (§5.12). |
| A signed-out visitor sees too much / too little | `AppSetting#access_mode` and the table in `access_control.rb`. Only GETs pass; unlisted actions fall through to Devise (§5.13). |
| Admin-only UI missing | `users.admin`; sources CRUD and default-list toggles are admin-gated. Check the impersonation banner first — an admin viewing as someone else has no admin powers by design (§5.6). |
